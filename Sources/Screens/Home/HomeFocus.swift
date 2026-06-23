import Foundation

/// Single focus space for the Home screen so we can react to focus moving
/// between the nav, the hero action row, and rail cards (drives hero
/// expand/collapse + spotlight, §6.3).
enum HomeFocus: Hashable {
    case nav(String)
    case heroWatch, heroMyList, heroInfo
    /// Event Detail's focusable long-description block (OK → full-text modal,
    /// §7). Lives here because Detail reuses the shared nav + rail components,
    /// which are bound to this focus space.
    case detailDescription
    /// Search screen query field + clear button (§8). Reuses the shared nav +
    /// rail components, so it shares this focus space too.
    case searchField, searchClear
    case card(UUID)
}

/// Left-nav items, top → bottom (§6.6). Settings is pinned to the bottom.
struct NavItemSpec: Identifiable {
    let id: String
    let label: String
    let systemImage: String
}

enum Nav {
    static let top: [NavItemSpec] = [
        .init(id: "search", label: "Search", systemImage: "magnifyingglass"),
        .init(id: "home", label: "Home", systemImage: "house.fill"),
        .init(id: "meetups", label: "Meetups", systemImage: "person.2.fill"),
        .init(id: "livestreams", label: "Livestreams", systemImage: "dot.radiowaves.left.and.right"),
        .init(id: "continue", label: "Continue Watching", systemImage: "play.circle.fill"),
        .init(id: "mylist", label: "My List", systemImage: "bookmark.fill"),
        .init(id: "mynotes", label: "My Notes", systemImage: "square.and.pencil"),
    ]
    static let settings = NavItemSpec(id: "settings", label: "Settings", systemImage: "gearshape.fill")
}
