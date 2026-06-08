import SwiftUI

/// Drives the Search screen (§8): debounced `GET /search?q=`, results split into
/// an Events rail + a Videos rail (rendered by the shared `RailsView`/`CardView`),
/// plus the profile labels for the left nav. 401s are handled centrally by the
/// API client (bounce to Pairing), so here we just surface an error state.
@MainActor
final class SearchViewModel: ObservableObject {
    enum Status { case prompt, loading, results, empty, error }

    @Published var query = ""
    @Published var status: Status = .prompt
    @Published var rails: [HomeRail] = []
    @Published var profileName = "Account"
    @Published var profileHandle = ""

    /// §8: minimum 2 chars, ~400 ms debounce, dedup identical queries.
    private let minChars = 2
    private let debounceMs: UInt64 = 400
    private var searchTask: Task<Void, Never>?
    private var lastQuery = ""
    private var didLoadProfile = false

    func loadProfile() async {
        guard !didLoadProfile else { return }
        didLoadProfile = true
        if let user = (try? await ApiClient.shared.me())?.user {
            profileName = user.preferredLabel
            profileHandle = user.telegramHandle ?? ""
        }
    }

    /// Called on every query change. Debounces, dedups, then searches (§8).
    func onQueryChanged() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchTask?.cancel()
        guard q.count >= minChars else {
            lastQuery = ""
            status = .prompt
            rails = []
            return
        }
        guard q != lastQuery else { return }
        status = .loading
        searchTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: self.debounceMs * 1_000_000)
            if Task.isCancelled { return }
            await self.run(q)
        }
    }

    private func run(_ q: String) async {
        lastQuery = q
        do {
            let res = try await ApiClient.shared.search(query: q)
            if Task.isCancelled { return }
            let events = (res.events ?? []).map {
                RailItem(media: $0, kind: .event, isContinueWatching: false, bookmarkBadge: nil)
            }
            let videos = (res.videos ?? []).map {
                RailItem(media: $0, kind: .video, isContinueWatching: false, bookmarkBadge: nil)
            }
            var built: [HomeRail] = []
            if !events.isEmpty { built.append(HomeRail(id: "sr_events", title: "Events", items: events)) }
            if !videos.isEmpty { built.append(HomeRail(id: "sr_videos", title: "Videos", items: videos)) }
            rails = built
            status = built.isEmpty ? .empty : .results
        } catch {
            if Task.isCancelled { return }
            status = .error
        }
    }
}
