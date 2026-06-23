import Foundation

/// Errors surfaced by `ApiClient`. `status` lets callers branch on
/// 401 (re-auth), 410/404 (expired pairing/compose code), etc.
enum ApiError: Error {
    case http(status: Int, body: String?)
    case network(String)
    case decoding(String)

    var status: Int? {
        if case let .http(status, _) = self { return status }
        return nil
    }
}

/// Posted when an authenticated request returns 401 while a token exists.
/// `AppRouter` observes this to wipe the token and return to Pairing (§2).
extension Notification.Name {
    static let reversionUnauthorized = Notification.Name("reversionUnauthorized")
}

/// HTTP client mirroring the §4 contract 1:1. Base
/// `https://reversion.app/api/mobile`. Bearer token injected on authed
/// calls from the Keychain. Retries transient failures up to 3× with
/// 300 / 800 / 1500 ms backoff; never retries 4xx or cancellation (§2).
final class ApiClient {
    static let shared = ApiClient()

    private let base = URL(string: "https://reversion.app/api/mobile")!
    private let session: URLSession
    private let decoder: JSONDecoder

    /// Backoff schedule in milliseconds (§2). Count drives max retries.
    private let backoffMs = [300, 800, 1500]

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = false
        session = URLSession(configuration: config)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    // MARK: - Pairing (no auth)

    func requestPairingCode(deviceName: String) async throws -> PairingCodeResponse {
        try await send(.post, "/device-auth/request",
                       body: ["device_name": deviceName], authed: false)
    }

    func pollPairingCode(_ code: String) async throws -> PairingPollResponse {
        let q = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code
        return try await send(.get, "/device-auth/poll?code=\(q)", authed: false)
    }

    // MARK: - Home / Events / Library / Me (authed)

    func home() async throws -> HomeResponse { try await send(.get, "/home") }

    func library() async throws -> LibraryResponse { try await send(.get, "/library") }

    /// `GET /my-notes` → all the user's notes grouped by video (§11.1).
    func myNotes() async throws -> MyNotesResponse { try await send(.get, "/my-notes") }

    func me() async throws -> MeResponse { try await send(.get, "/me") }

    /// `GET /legal/{document}` → `{ title, html }` for the in-app legal reader
    /// (§10.3). No auth. `document` is `privacy-stewardship-notice` or
    /// `private-member-digital-agreement`.
    func legal(document: String) async throws -> LegalResponse {
        try await send(.get, "/legal/\(document)", authed: false)
    }

    /// `type` filters server-side: `"meetup"` → `location_type != 'online'`
    /// (in-person/hybrid), `"livestream"` → online only. Nil returns all (§6.7).
    func events(page: Int = 1, perPage: Int = 50, type: String? = nil) async throws -> EventsResponse {
        var path = "/events?page=\(page)&per_page=\(perPage)&exclude_future=1"
        if let type { path += "&type=\(type)" }
        return try await send(.get, path)
    }

    func event(id: Int) async throws -> EventDetailResponse {
        try await send(.get, "/events/\(id)")
    }

    func search(query: String) async throws -> SearchResponse {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return try await send(.get, "/search?q=\(q)")
    }

    // MARK: - Player: stream, progress, notes (§9)

    /// `GET /videos/{id}/stream-url` → HLS URL + meta + annotations +
    /// chapters + next_video (§9.2).
    func streamUrl(videoId: Int) async throws -> StreamUrlResponse {
        try await send(.get, "/videos/\(videoId)/stream-url")
    }

    /// `PUT /videos/{id}/progress` → 204. Throttled save (§9.13).
    @discardableResult
    func saveProgress(videoId: Int, seconds: Int) async throws -> EmptyResponse {
        try await send(.put, "/videos/\(videoId)/progress", body: ["seconds": seconds])
    }

    /// `GET /videos/{id}/notes` → the viewer's private notes (§9.6).
    func notes(videoId: Int) async throws -> NotesResponse {
        try await send(.get, "/videos/\(videoId)/notes")
    }

    /// `DELETE /videos/{id}/notes/{noteId}` (§9.8).
    @discardableResult
    func deleteNote(videoId: Int, noteId: Int) async throws -> EmptyResponse {
        try await send(.delete, "/videos/\(videoId)/notes/\(noteId)")
    }

    // MARK: - TV-note QR companion (§9.7)

    /// `POST /tv-notes/request` — mint a phone-compose code (Edit passes
    /// `noteId`). Returns `scan_url` + `code` + `short_url`.
    func requestTvNoteCode(videoId: Int, seconds: Int, noteId: Int? = nil) async throws -> TvNoteRequestResponse {
        var body: [String: Any] = ["video_id": videoId, "seconds": seconds]
        if let noteId { body["note_id"] = noteId }
        return try await send(.post, "/tv-notes/request", body: body)
    }

    /// `GET /tv-notes/poll?code=` — pending / scanned / completed / expired.
    /// 410/404 surface as `ApiError.http` so callers can show the expiry panel.
    func pollTvNoteCode(_ code: String) async throws -> TvNotePollResponse {
        let q = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code
        return try await send(.get, "/tv-notes/poll?code=\(q)")
    }

    /// `DELETE /tv-notes/{code}` — cancel an unfinished code on close (§9.7).
    @discardableResult
    func cancelTvNoteCode(_ code: String) async throws -> EmptyResponse {
        let q = code.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? code
        return try await send(.delete, "/tv-notes/\(q)")
    }

    // MARK: - Bookmarks (idempotent, 204)

    @discardableResult
    func addEventBookmark(eventId: Int) async throws -> EmptyResponse {
        try await send(.post, "/events/\(eventId)/bookmark", body: [:])
    }

    @discardableResult
    func removeEventBookmark(eventId: Int) async throws -> EmptyResponse {
        try await send(.delete, "/events/\(eventId)/bookmark")
    }

    @discardableResult
    func addVideoBookmark(videoId: Int) async throws -> EmptyResponse {
        try await send(.post, "/videos/\(videoId)/bookmark", body: [:])
    }

    @discardableResult
    func removeVideoBookmark(videoId: Int) async throws -> EmptyResponse {
        try await send(.delete, "/videos/\(videoId)/bookmark")
    }

    // MARK: - Core request pipeline

    private enum Method: String { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

    private func send<T: Decodable>(
        _ method: Method,
        _ path: String,
        body: [String: Any]? = nil,
        authed: Bool = true
    ) async throws -> T {
        let data = try await raw(method, path, body: body, authed: authed)
        if data.isEmpty, let empty = EmptyResponse() as? T { return empty }
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw ApiError.decoding(String(describing: error))
        }
    }

    /// Performs the request with retry + 401 handling, returning the raw body.
    private func raw(
        _ method: Method,
        _ path: String,
        body: [String: Any]?,
        authed: Bool
    ) async throws -> Data {
        var request = URLRequest(url: base.appendingPathComponentSafe(path))
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if authed, let token = KeychainTokenStore.token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }

        var lastError: Error = ApiError.network("Unknown")
        for attempt in 0...backoffMs.count {
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw ApiError.network("Bad response")
                }
                switch http.statusCode {
                case 200..<300:
                    return data
                case 401 where authed:
                    // No refresh flow — wipe token and bounce to Pairing.
                    KeychainTokenStore.clear()
                    await MainActor.run {
                        NotificationCenter.default.post(name: .reversionUnauthorized, object: nil)
                    }
                    throw ApiError.http(status: 401, body: String(data: data, encoding: .utf8))
                case 400..<500:
                    // 4xx is terminal — never retry (incl. 410/404 pairing expiry).
                    throw ApiError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
                default:
                    // 5xx — retry per backoff.
                    throw ApiError.http(status: http.statusCode, body: String(data: data, encoding: .utf8))
                }
            } catch let error as ApiError {
                lastError = error
                // Only retry transient (5xx / network); 4xx is terminal.
                if let status = error.status, (400..<500).contains(status) { throw error }
                if attempt < backoffMs.count {
                    try? await Task.sleep(nanoseconds: UInt64(backoffMs[attempt]) * 1_000_000)
                    if Task.isCancelled { throw CancellationError() }
                    continue
                }
                throw error
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = ApiError.network(error.localizedDescription)
                if attempt < backoffMs.count {
                    try? await Task.sleep(nanoseconds: UInt64(backoffMs[attempt]) * 1_000_000)
                    if Task.isCancelled { throw CancellationError() }
                    continue
                }
                throw lastError
            }
        }
        throw lastError
    }
}

private extension URL {
    /// Appends a path string that may already contain a `?query`.
    func appendingPathComponentSafe(_ path: String) -> URL {
        URL(string: absoluteString + path) ?? self
    }
}
