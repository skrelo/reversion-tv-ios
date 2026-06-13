import SwiftUI

/// Catalog views reachable from the left nav (in-place, not a push, §6.7).
enum Catalog: String, Hashable {
    case meetups, livestreams, continueWatching, myList
}

@MainActor
final class HomeViewModel: ObservableObject {
    @Published var loading = true
    @Published var error: String?

    @Published var heroItems: [MediaItem] = []
    @Published var rails: [HomeRail] = []
    @Published var profileName = "Account"
    @Published var profileHandle = ""
    @Published var profilePhotoUrl = ""

    /// Active catalog view (nil = default home).
    @Published var catalog: Catalog?

    // Raw payloads kept for catalog rebuilds (no extra API calls, §6.7).
    private var continueWatchingRaw: [MediaItem] = []
    private var bookmarksRaw: [MediaItem] = []
    private var eventBookmarksRaw: [MediaItem] = []
    private var recentEventsRaw: [MediaItem] = []
    private var recentLivestreamsRaw: [MediaItem] = []
    private var allEvents: [MediaItem]?
    /// Event ids currently bookmarked (drives the hero My List icon, optimistic).
    @Published private(set) var bookmarkedEventIds: Set<Int> = []

    // MARK: - Load

    /// Parallel load of /home + /library + /me; library/me failures don't
    /// kill the page (§6.1). `silent` skips the spinner for return refreshes.
    func load(silent: Bool = false) async {
        if !silent { loading = true; error = nil }
        do {
            async let home = ApiClient.shared.home()
            async let library = try? await ApiClient.shared.library()
            async let me = try? await ApiClient.shared.me()
            let (homeRes, libRes, meRes) = try await (home, library, me)

            heroItems = homeRes.heroCarousel ?? []
            continueWatchingRaw = homeRes.continueWatching ?? libRes?.continueWatching ?? []
            recentEventsRaw = homeRes.recentEvents ?? []
            recentLivestreamsRaw = homeRes.recentLivestreams ?? []
            bookmarksRaw = libRes?.bookmarks ?? []
            eventBookmarksRaw = libRes?.eventBookmarks ?? []
            bookmarkedEventIds = Set(eventBookmarksRaw.compactMap { $0.id })

            if let user = meRes?.user {
                profileName = user.preferredLabel
                profileHandle = user.telegramHandle ?? ""
                profilePhotoUrl = user.profilePhotoUrl ?? ""
            }

            // Hero fallback = first recent event wrapped as a featured item.
            if heroItems.isEmpty, let first = recentEventsRaw.first { heroItems = [first] }

            rebuildRails()
            loading = false
        } catch let e as ApiError where e.status == 401 {
            // 401 is handled globally (token wiped + bounce to Pairing).
            loading = false
        } catch {
            self.error = "Could not load content. Check your connection."
            loading = false
        }
    }

    // MARK: - Rails

    private func rebuildRails() {
        if let catalog { rails = catalogRails(catalog); return }
        var built: [HomeRail] = []

        if !continueWatchingRaw.isEmpty {
            built.append(HomeRail(id: "cw", title: "Continue Watching",
                                  items: continueWatchingRaw.map { videoItem($0, continueWatching: true) }))
        }
        let myList = buildMyList()
        if !myList.isEmpty {
            built.append(HomeRail(id: "ml", title: "My List", items: myList))
        }
        if !recentEventsRaw.isEmpty {
            built.append(HomeRail(id: "events", title: "Meetups",
                                  items: recentEventsRaw.map { eventItem($0) }))
        }
        if !recentLivestreamsRaw.isEmpty {
            built.append(HomeRail(id: "ls", title: "Livestreams",
                                  items: recentLivestreamsRaw.map { eventItem($0) }))
        }
        rails = built
    }

    private func videoItem(_ m: MediaItem, continueWatching: Bool) -> RailItem {
        RailItem(media: m, kind: .video, isContinueWatching: continueWatching, bookmarkBadge: nil)
    }
    private func eventItem(_ m: MediaItem) -> RailItem {
        RailItem(media: m, kind: .event, isContinueWatching: false, bookmarkBadge: nil)
    }

    private func buildMyList() -> [RailItem] {
        let events = eventBookmarksRaw.map {
            RailItem(media: $0, kind: .event, isContinueWatching: false, bookmarkBadge: "EVENT")
        }
        let videos = bookmarksRaw.map {
            RailItem(media: $0, kind: .video, isContinueWatching: false, bookmarkBadge: "VIDEO")
        }
        return (events + videos).sorted {
            ($0.media.bookmarkedAt ?? "") > ($1.media.bookmarkedAt ?? "")
        }
    }

    // MARK: - Catalog (§6.7)

    func enterCatalog(_ type: Catalog) {
        catalog = type
        rails = catalogRails(type)
        // Meetups lazily loads the full event catalog — server-filtered to
        // in-person/hybrid events (location_type != 'online') via ?type=meetup
        // so livestreams never leak into the Meetups view (§6.7).
        if type == .meetups, allEvents == nil {
            Task {
                if let res = try? await ApiClient.shared.events(type: "meetup") {
                    allEvents = res.items
                    if catalog == .meetups { rails = catalogRails(.meetups) }
                }
            }
        }
    }

    func exitCatalog() {
        catalog = nil
        rebuildRails()
    }

    private func catalogRails(_ type: Catalog) -> [HomeRail] {
        switch type {
        case .meetups:
            return yearGrouped(allEvents ?? recentEventsRaw, keyPrefix: "meetups", ungrouped: "Other")
        case .livestreams:
            return yearGrouped(recentLivestreamsRaw, keyPrefix: "livestreams", ungrouped: "Collections")
        case .continueWatching:
            guard !continueWatchingRaw.isEmpty else { return [] }
            return [HomeRail(id: "cw", title: "Continue Watching",
                             items: continueWatchingRaw.map { videoItem($0, continueWatching: true) })]
        case .myList:
            let ml = buildMyList()
            return ml.isEmpty ? [] : [HomeRail(id: "ml", title: "My List", items: ml)]
        }
    }

    /// Year-grouped rails (newest first; unparseable → one bottom bucket, §6.7).
    private func yearGrouped(_ events: [MediaItem], keyPrefix: String, ungrouped: String) -> [HomeRail] {
        var groups: [Int: [MediaItem]] = [:]
        for ev in events {
            let year = Self.parseYear(ev.sessionDate) ?? 0
            groups[year, default: []].append(ev)
        }
        var years = groups.keys.filter { $0 > 0 }.sorted(by: >)
        if groups[0] != nil { years.append(0) }
        return years.compactMap { year in
            guard let items = groups[year], !items.isEmpty else { return nil }
            return HomeRail(id: "\(keyPrefix)_\(year)",
                            title: year == 0 ? ungrouped : String(year),
                            items: items.map { eventItem($0) })
        }
    }

    private static func parseYear(_ date: String?) -> Int? {
        guard let date else { return nil }
        guard let range = date.range(of: "20\\d{2}", options: .regularExpression) else { return nil }
        return Int(date[range])
    }

    // MARK: - Bookmarks (optimistic, reconciled via library(), §6.1/§6.4)

    func toggleEventBookmark(_ eventId: Int) {
        let wasIn = bookmarkedEventIds.contains(eventId)
        if wasIn { bookmarkedEventIds.remove(eventId) } else { bookmarkedEventIds.insert(eventId) }
        Task {
            do {
                if wasIn {
                    try await ApiClient.shared.removeEventBookmark(eventId: eventId)
                } else {
                    try await ApiClient.shared.addEventBookmark(eventId: eventId)
                }
                if let lib = try? await ApiClient.shared.library() {
                    eventBookmarksRaw = lib.eventBookmarks ?? []
                    bookmarksRaw = lib.bookmarks ?? []
                    bookmarkedEventIds = Set(eventBookmarksRaw.compactMap { $0.id })
                    if catalog == nil { rebuildRails() } else if let c = catalog { rails = catalogRails(c) }
                }
            } catch {
                // Revert on failure.
                if wasIn { bookmarkedEventIds.insert(eventId) } else { bookmarkedEventIds.remove(eventId) }
            }
        }
    }

    func isEventBookmarked(_ eventId: Int?) -> Bool {
        guard let eventId else { return false }
        return bookmarkedEventIds.contains(eventId)
    }
}
