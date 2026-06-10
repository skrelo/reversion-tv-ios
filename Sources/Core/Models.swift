import Foundation

/// Placeholder for 204 / empty-body responses.
struct EmptyResponse: Decodable {}

// MARK: - Pairing (§5)

/// `POST /device-auth/request` → mint a pairing code.
struct PairingCodeResponse: Decodable {
    let code: String
    /// Seconds until the code expires. Decoded from `expires_in`.
    let expiresIn: Int?
    /// Suggested poll cadence in seconds. Decoded from `poll_interval`.
    let pollInterval: Int?
}

/// `GET /device-auth/poll?code=` → 202 pending / 200 authorized + token.
struct PairingPollResponse: Decodable {
    let status: String?
    let token: String?

    var isAuthorized: Bool { status == "authorized" && token != nil }
}

// MARK: - Media (events + videos share one flexible shape, §4.1)

/// A nested playable video reference (`first_video`,
/// `last_in_progress_video`, `next_video`).
struct VideoRef: Decodable {
    let id: Int?
    let progressSeconds: Int?
    /// Present on `last_in_progress_video` so event cards can compute the
    /// RED resume bar fraction (progress / duration) without a flat field.
    let durationSeconds: Int?
}

/// A nested parent event (the `event { … }` shape on a video, §4.1).
struct EventRef: Decodable {
    let id: Int?
    let name: String?
    let title: String?
    let backdropUrl: String?
    let posterUrl: String?
    let wordmarkUrl: String?
    let sessionDate: String?
    let videoCount: Int?
    let tvSubtitle: String?
    let shortDescription: String?
}

/// One content item — works for both events (meetups/livestreams) and
/// videos. Most fields are optional; resolve the dual video shape (flat
/// `event_*` fields vs nested `event`) via the computed helpers below.
struct MediaItem: Decodable {
    let id: Int?
    let title: String?
    let backdropUrl: String?
    let posterUrl: String?
    let cardPosterUrl: String?
    let coverUrl: String?
    let wordmarkUrl: String?
    let tvSubtitle: String?
    let shortDescription: String?
    /// Full long-form description (event-detail payload only, §7).
    let description: String?
    let sessionDate: String?
    let videoCount: Int?
    let isNew: Bool?
    let hasNewVideo: Bool?
    let durationSeconds: Int?
    let progressSeconds: Int?
    let bookmarkedAt: String?
    let videoDate: String?

    // Flat parent-event fields carried by a video.
    let eventId: Int?
    let eventTitle: String?
    let eventWordmarkUrl: String?
    let eventSessionDate: String?
    let eventVideoCount: Int?
    let eventTvSubtitle: String?
    let eventShortDescription: String?

    // Nested shapes.
    let event: EventRef?
    let firstVideo: VideoRef?
    let lastInProgressVideo: VideoRef?

    // MARK: Resolved helpers (mirror Android resolvedEventId/Title/Cover)

    var resolvedEventId: Int? { eventId ?? event?.id }
    var resolvedEventTitle: String {
        eventTitle ?? event?.name ?? event?.title ?? ""
    }

    /// CTA target + label for hero/detail Watch buttons (§6.4).
    var watchTarget: VideoRef? { lastInProgressVideo ?? firstVideo }
    var watchLabel: String { lastInProgressVideo != nil ? "Continue" : "Watch" }
}

// MARK: - Endpoint envelopes

struct HomeResponse: Decodable {
    let heroCarousel: [MediaItem]?
    let continueWatching: [MediaItem]?
    let upcomingEvents: [MediaItem]?
    let recentEvents: [MediaItem]?
    let recentLivestreams: [MediaItem]?
}

struct LibraryResponse: Decodable {
    let continueWatching: [MediaItem]?
    let bookmarks: [MediaItem]?
    let eventBookmarks: [MediaItem]?
}

struct EventsResponse: Decodable {
    let events: [MediaItem]?
    let data: [MediaItem]?
    var items: [MediaItem] { events ?? data ?? [] }
}

struct EventDetailResponse: Decodable {
    let event: MediaItem?
    let videos: [MediaItem]?
}

struct SearchResponse: Decodable {
    let events: [MediaItem]?
    let videos: [MediaItem]?
}

struct MeResponse: Decodable {
    let user: User?
}

/// `GET /legal/{document}` → in-app legal reader content (§10.3). No auth.
struct LegalResponse: Decodable {
    let title: String?
    let html: String?
}

struct User: Decodable {
    let id: Int?
    let name: String?
    let displayName: String?
    let email: String?
    let telegramHandle: String?
    let profilePhotoUrl: String?
    let memberSince: String?

    /// Best label for the nav/profile (display_name → name → email local part).
    var preferredLabel: String {
        if let d = displayName, !d.isEmpty { return d }
        if let n = name, !n.isEmpty { return n }
        if let e = email, let local = e.split(separator: "@").first { return String(local) }
        return "Account"
    }
}
