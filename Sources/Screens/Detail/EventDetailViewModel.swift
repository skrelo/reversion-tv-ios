import SwiftUI

/// Drives the Event Detail screen (§7): loads `GET /events/{id}` (event +
/// videos), tracks the event bookmark, and exposes the videos as `RailItem`s so
/// the shared `RailsView`/`CardView` render the "Videos" rail.
@MainActor
final class EventDetailViewModel: ObservableObject {
    @Published var event: MediaItem?
    @Published var videos: [RailItem] = []
    @Published var loading = true
    @Published var error: String?
    @Published var isBookmarked = false
    @Published var profileName = "Account"
    @Published var profileHandle = ""

    private let eventId: Int
    private var didLoad = false

    init(eventId: Int) { self.eventId = eventId }

    func load() async {
        guard !didLoad else { return }
        didLoad = true
        loading = true
        error = nil
        do {
            let resp = try await ApiClient.shared.event(id: eventId)
            event = resp.event
            videos = (resp.videos ?? []).map {
                RailItem(media: $0, kind: .video, isContinueWatching: false, bookmarkBadge: nil)
            }
            if let user = (try? await ApiClient.shared.me())?.user {
                profileName = user.preferredLabel
                profileHandle = user.telegramHandle ?? ""
            }
            // Reconcile bookmark state from the library set (the detail payload
            // itself doesn't carry a per-user bookmarked flag).
            await refreshBookmarkState()
        } catch is CancellationError {
            // View went away mid-flight; let it retry on next appear.
            didLoad = false
        } catch {
            self.error = "Couldn't load this event."
        }
        loading = false
    }

    /// Single rail wrapping the videos, for `RailsView`.
    var videoRails: [HomeRail] {
        guard !videos.isEmpty else { return [] }
        return [HomeRail(id: "videos", title: "Videos", items: videos)]
    }

    /// Watch CTA: resume / start / view (§7). `nil` target → no playable video.
    var watchTarget: VideoRef? { event?.watchTarget }
    var watchLabel: String {
        guard let event else { return "View" }
        return event.watchTarget != nil ? event.watchLabel : "View"
    }

    func toggleBookmark() {
        guard let id = event?.id else { return }
        let next = !isBookmarked
        isBookmarked = next
        Task {
            do {
                if next { try await ApiClient.shared.addEventBookmark(eventId: id) }
                else { try await ApiClient.shared.removeEventBookmark(eventId: id) }
            } catch {
                // Revert on failure.
                await MainActor.run { self.isBookmarked = !next }
            }
        }
    }

    private func refreshBookmarkState() async {
        guard let id = event?.id else { return }
        if let lib = try? await ApiClient.shared.library() {
            let ids = Set((lib.eventBookmarks ?? []).compactMap { $0.id })
            isBookmarked = ids.contains(id)
        }
    }
}
