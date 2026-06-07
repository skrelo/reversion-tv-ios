import Foundation

enum ItemKind { case video, event }

/// Spotlight payload — ALWAYS describes the parent EVENT, never the video
/// (§6.3). Derived from a `MediaItem` the same way Android's toCardItem does.
struct SpotlightData: Equatable {
    let backdropUrl: String?
    let wordmarkUrl: String?
    let title: String
    let videoTitle: String?
    let sessionDate: String?
    let videoCount: Int
    let tagline: String?
    let description: String?
}

/// A single card in a rail, with display metadata resolved up-front.
struct RailItem: Identifiable {
    let id = UUID()
    let media: MediaItem
    let kind: ItemKind
    /// Continue-watching tile (center play glyph + progress bar).
    let isContinueWatching: Bool
    /// My List type chip: "EVENT" / "VIDEO" (nil elsewhere).
    let bookmarkBadge: String?

    var isVideo: Bool { kind == .video }

    /// Routing payload: video cards play; event cards open detail (§6.5).
    /// CW tiles are event-shaped but resume the event's last-watched video.
    var videoId: Int? { kind == .video ? media.id : nil }
    var eventId: Int? {
        switch kind {
        case .video: return media.resolvedEventId
        case .event: return media.id
        }
    }
    var eventTitle: String? {
        kind == .video ? media.resolvedEventTitle : (media.title)
    }

    /// RED "resume" bar fraction (§6.5). Shown on ANY card whose parent
    /// event has an in-progress video, on every rail:
    ///   - video cards (CW, started bookmarks): flat progress/duration.
    ///   - event cards (Meetups/Livestreams/My List): the event's
    ///     `last_in_progress_video` (which carries duration).
    var progressFraction: Double {
        if kind == .event, let lip = media.lastInProgressVideo {
            return Self.fraction(lip.progressSeconds, lip.durationSeconds)
        }
        return Self.fraction(media.progressSeconds, media.durationSeconds)
    }

    private static func fraction(_ watched: Int?, _ dur: Int?) -> Double {
        guard let dur, dur > 0, let watched, watched > 0 else { return 0 }
        return min(1.0, Double(watched) / Double(dur))
    }

    var spotlight: SpotlightData {
        let nested = media.event
        let backdrop = (nested?.backdropUrl ?? nested?.posterUrl)
            ?? media.backdropUrl ?? media.posterUrl ?? media.coverUrl ?? media.cardPosterUrl
        let wordmark = media.eventWordmarkUrl ?? nested?.wordmarkUrl ?? media.wordmarkUrl
        let title = (media.resolvedEventTitle.isEmpty ? (media.title ?? "") : media.resolvedEventTitle)
        return SpotlightData(
            backdropUrl: backdrop,
            wordmarkUrl: wordmark,
            title: title,
            videoTitle: bookmarkBadge == "VIDEO" ? media.title : nil,
            sessionDate: media.eventSessionDate ?? nested?.sessionDate ?? media.sessionDate,
            videoCount: media.eventVideoCount ?? nested?.videoCount ?? media.videoCount ?? 0,
            tagline: media.eventTvSubtitle ?? nested?.tvSubtitle ?? media.tvSubtitle,
            description: media.eventShortDescription ?? nested?.shortDescription ?? media.shortDescription
        )
    }
}

struct HomeRail: Identifiable {
    let id: String
    let title: String
    let items: [RailItem]
}
