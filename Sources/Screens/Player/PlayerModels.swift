import Foundation

// MARK: - Stream payload (§9.2)

/// `GET /videos/{id}/stream-url`. Mirrors `VideosController::streamUrl`.
struct StreamUrlResponse: Decodable {
    let videoId: Int?
    let title: String?
    let eventId: Int?
    let eventTitle: String?
    /// Event wordmark for the Netflix-style pause overlay (§9.10).
    let wordmarkUrl: String?
    let hlsUrl: String?
    let coverUrl: String?
    let hasCaptions: Bool?
    /// Side-loadable WebVTT track (may be nil even when `hasCaptions`).
    let captionsUrl: String?
    let durationSeconds: Int?
    let bookmarked: Bool?
    let progressSeconds: Int?
    let annotations: [Annotation]?
    let chapters: [Chapter]?
    let nextVideo: NextVideo?
}

/// A timecoded chapter marker (§9.2). Surfaced via the Chapters pop-up.
struct Chapter: Decodable, Identifiable, Equatable {
    let id: Int?
    let title: String?
    let startsAtSeconds: Int?

    var startsAt: Double { Double(startsAtSeconds ?? 0) }
}

/// A coach-authored, timecoded annotation (gold marker, §9.6).
struct Annotation: Decodable {
    let id: Int?
    let title: String?
    let body: String?
    let imageUrl: String?
    let startsAtSeconds: Int?
}

/// The chrome's Next-video target (§9.2).
struct NextVideo: Decodable {
    let id: Int?
    let title: String?
}

// MARK: - Private notes (§9.6)

struct NotesResponse: Decodable {
    let notes: [NoteItem]?
}

struct NoteItem: Decodable {
    let id: Int?
    let seconds: Int?
    let title: String?
    let body: String?
}

// MARK: - TV-note QR companion (§9.7)

struct TvNoteRequestResponse: Decodable {
    let code: String?
    let scanUrl: String?
    let shortUrl: String?
    let pollInterval: Int?
}

struct TvNotePollResponse: Decodable {
    /// pending | scanned | completed | cancelled | expired | invalid.
    let status: String?
    let note: NoteItem?
}

// MARK: - Unified marker (annotation + note, §9.6)

/// Merged, type-normalized marker so the chip / popup / detail UI never
/// branches on type for layout. Built from the stream payload's annotations
/// + the separately-fetched private notes, sorted by timecode.
struct Marker: Identifiable, Equatable {
    enum Kind { case annotation, note }

    /// Stable key (`a<id>` / `n<id>`) — `Identifiable` id + popup fired-state key.
    let key: String
    let kind: Kind
    /// The backing annotation/note row id (used for delete/edit).
    let entityId: Int
    let startsAt: Double
    let title: String
    /// Raw HTML body (for link extraction → QR).
    let body: String
    /// HTML-stripped single-block body text (chips / detail / popup).
    let bodyText: String
    /// Top-level `image_url` + every `<img>` in the body, deduped, in order
    /// (§9.8). Drives the detail card image area + the image viewer.
    let images: [String]
    /// First webpage `<a href>` (with `<img>` stripped first so an image src is
    /// never mistaken for a link, §9.6/§9.8). Powers the detail-card QR / the
    /// popup link text. Nil when the body has no web link.
    let link: String?

    var id: String { key }
    var isNote: Bool { kind == .note }

    static func == (lhs: Marker, rhs: Marker) -> Bool { lhs.key == rhs.key }
}

enum Markers {
    /// Merge annotations + notes into one chronologically-sorted list (§9.6).
    static func build(annotations: [Annotation], notes: [NoteItem]) -> [Marker] {
        var out: [Marker] = []

        for a in annotations {
            guard let id = a.id else { continue }
            out.append(Marker(
                key: "a\(id)",
                kind: .annotation,
                entityId: id,
                startsAt: Double(a.startsAtSeconds ?? 0),
                title: a.title ?? "",
                body: a.body ?? "",
                bodyText: Html.strip(a.body).replacingOccurrences(of: "\n", with: " "),
                images: collectImages(topLevel: a.imageUrl, body: a.body),
                link: Html.firstWebLink(a.body)
            ))
        }

        for n in notes {
            guard let id = n.id else { continue }
            out.append(Marker(
                key: "n\(id)",
                kind: .note,
                entityId: id,
                startsAt: Double(n.seconds ?? 0),
                title: n.title ?? "",
                body: n.body ?? "",
                bodyText: Html.strip(n.body).replacingOccurrences(of: "\n", with: " "),
                images: collectImages(topLevel: nil, body: n.body),
                link: Html.firstWebLink(n.body)
            ))
        }

        out.sort { $0.startsAt < $1.startsAt }
        return out
    }

    /// Top-level `image_url` first, then every `<img>` in the body, deduped
    /// (§9.8). Image-vs-link is decided by the tag, so body images come from
    /// `<img>` extraction — never from sniffing link URLs.
    private static func collectImages(topLevel: String?, body: String?) -> [String] {
        var images: [String] = []
        if let u = topLevel, !u.isEmpty { images.append(u) }
        for s in Html.imageSources(body) where !images.contains(s) { images.append(s) }
        return images
    }

    /// Index of the marker nearest a time (auto-center + focus landing, §9.6).
    /// Returns nil for an empty list.
    static func nearestIndex(_ markers: [Marker], time: Double) -> Int? {
        guard !markers.isEmpty else { return nil }
        var best = 0
        var bestDist = Double.infinity
        for (i, m) in markers.enumerated() {
            let d = abs(m.startsAt - time)
            if d < bestDist { bestDist = d; best = i }
        }
        return best
    }
}
