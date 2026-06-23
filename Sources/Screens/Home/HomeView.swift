import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model = HomeViewModel()

    /// tvOS keeps the app suspended in memory for long stretches and rarely
    /// cold-launches, so the initial `.task` load can be days stale. Refresh
    /// Home whenever the user lands on it (returns from a pushed screen) and
    /// as a backstop when the app resumes — so newly-granted entitlements
    /// (added on the web) show up without a relaunch. Backgrounding alone is
    /// unreliable (often = TV powered off), so landing is the primary trigger.
    @Environment(\.scenePhase) private var scenePhase
    @State private var lastRefresh = Date.distantPast

    @FocusState private var focus: HomeFocus?
    @State private var heroExpanded = true
    @State private var spotlight: SpotlightData?
    @State private var slideIndex = 0
    /// Carousel paging direction for the slide transition (true = forward/next).
    /// Set immediately before each `slideIndex` change so the move transition
    /// reads the correct edge in the same render pass.
    @State private var slideForward = true
    @State private var didInitialFocus = false
    /// True while a nav item holds focus. Disables the content's focusability
    /// so DOWN from the bottom nav item can't escape into the rails (it
    /// hard-stops) and RIGHT has nothing to grab — we return to content
    /// explicitly instead. Mirrors Android/Tizen's "nav traps focus" model.
    @State private var navOpen = false
    /// The content element to restore when leaving the nav (RIGHT).
    @State private var lastContentFocus: HomeFocus = .heroWatch
    /// Per-rail settled-column memory (§6.5). Keyed by `HomeRail.id`. Crossing
    /// INTO a rail lands on its remembered column if the user has visited it
    /// before, otherwise column 0 — NOT the geometric same-column the focus
    /// engine would pick. Updated whenever a card settles.
    @State private var lastColumnByRail: [String: Int] = [:]
    /// Rails the user has actually landed on. A rail not in this set defaults to
    /// column 0 on first entry; a visited rail restores `lastColumnByRail`.
    @State private var visitedRails: Set<String> = []

    private struct AutoKey: Hashable { let expanded: Bool; let index: Int; let count: Int; let focus: HomeFocus? }

    /// **Stable rails anchor (cross-platform fix for the CW-clip-on-DOWN bug).**
    /// The hero *content* + the rails below it are laid out against a CONSTANT
    /// anchor (`heroAnchorHeight`) so the rails NEVER reflow when focus crosses
    /// from the carousel into the first rail. Only the *backdrop image* height
    /// animates (`heroBackdropHeight`) to give the "hero drops to ~60%" look.
    /// Reflowing the rails on the same frame as the focus move + scroll-to-card
    /// is what clipped the first rail's title on the initial DOWN (it settled
    /// only after a second focus move like RIGHT) — anchoring removes the race.
    private let heroAnchorHeight: CGFloat = 600
    private var heroBackdropHeight: CGFloat { heroExpanded ? 720 : 600 }

    var body: some View {
        contentLayer
        .task { if model.loading { await model.load(); lastRefresh = Date() } }
        // Auto-advance every 8 s. Keyed on `focus` too, so moving between the
        // carousel's own buttons (Watch / My List / Info) RESTARTS the 8 s
        // clock instead of letting the slide flip out from under the user
        // mid-interaction (§6.4).
        .task(id: AutoKey(expanded: heroExpanded, index: slideIndex, count: model.heroItems.count, focus: focus)) {
            guard heroExpanded, model.heroItems.count > 1, model.catalog == nil, isHeroFocus(focus) else { return }
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            if !Task.isCancelled {
                slideForward = true   // auto-advance always pages forward (last → 0 wraps forward)
                withAnimation(.easeInOut(duration: 0.5)) {
                    slideIndex = (slideIndex + 1) % model.heroItems.count
                }
            }
        }
        // Primary refresh: user lands back on Home from any pushed screen
        // (video/detail/search/settings). Picks up entitlement/content changes.
        .onChange(of: router.path) { oldValue, newValue in
            if newValue.isEmpty && !oldValue.isEmpty { refreshHome() }
        }
        // Backstop: app resumes to active (e.g. switched apps and back).
        .onChange(of: scenePhase) { _, newValue in
            if newValue == .active { refreshHome() }
        }
        .onChange(of: focus) { oldValue, newValue in handleFocusChange(from: oldValue, to: newValue) }
        .onChange(of: model.loading) { _, isLoading in
            if !isLoading { setInitialFocus() }
        }
        .onExitCommand {
            if model.catalog != nil {
                model.exitCatalog()
                heroExpanded = true
                spotlight = nil
                focusFirstRailOrNav()
            }
            // else: at Home root — let the system handle it.
        }
    }

    // MARK: - Layers

    /// True when the API call succeeded but the account has no entitled content.
    private var isEntitlementEmpty: Bool {
        !model.loading && model.error == nil && model.heroItems.isEmpty && model.rails.isEmpty
    }

    @ViewBuilder
    private var contentLayer: some View {
        if let error = model.error {
            ZStack { Theme.bg.ignoresSafeArea()
                Text(error).font(.system(size: 30)).foregroundStyle(Theme.textDim) }
        } else if model.loading {
            ZStack { Theme.bg.ignoresSafeArea(); ProgressView().scaleEffect(2) }
        } else if isEntitlementEmpty {
            emptyStateView
        } else {
            ZStack(alignment: .topLeading) {
                Theme.bg.ignoresSafeArea()
                // Full-bleed backdrop behind everything; height tracks the
                // hero expand/collapse. The nav gradient + content draw on top.
                HeroBackdropView(
                    url: heroBackdropURL,
                    slideForward: slideForward,
                    sliding: heroExpanded && model.catalog == nil
                )
                    .frame(height: heroBackdropHeight)
                    // Clip to the hero band so a crossfading backdrop can't bleed
                    // edge-to-edge down behind the rails during a slide change.
                    .clipped()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.32), value: heroExpanded)

                // Content runs full-bleed; a leading inset clears the
                // collapsed nav strip so nothing hides behind the icons.
                VStack(alignment: .leading, spacing: 0) {
                    HeroContentView(
                        heroItems: model.catalog == nil ? model.heroItems : [],
                        slideIndex: slideIndex,
                        spotlight: spotlight,
                        expanded: model.catalog == nil ? heroExpanded : false,
                        isInMyList: model.isEventBookmarked(currentHeroEventId),
                        slideForward: slideForward,
                        focus: $focus,
                        onPlay: { router.push(.player(videoId: $0)) },
                        onInfo: { router.push(.eventDetail(id: $0, title: currentHeroTitle)) },
                        onToggleMyList: { model.toggleEventBookmark($0) },
                        onLeftEdge: heroLeftEdge,
                        onRightEdge: heroRightEdge
                    )
                    .frame(height: heroAnchorHeight)
                    .focusSection()

                    railsArea
                        .focusSection()
                }
                .padding(.leading, LeftNavView.stripWidth)
                // While the nav is open, content can't take focus — so the
                // nav's DOWN hard-stops (can't fall into the rails) and LEFT
                // from a collapsed-strip-adjacent card still opens the nav.
                .disabled(navOpen)

                // Nav overlays the content's left edge (gradient over hero/
                // rails). LEFT from the carousel / card index 0 opens it (the
                // collapsed strip sits to the left of the content); RIGHT
                // returns to the content element we left from.
                LeftNavView(
                    activeId: activeNavId,
                    profileName: model.profileName,
                    profileHandle: model.profileHandle,
                    profilePhotoUrl: model.profilePhotoUrl,
                    focus: $focus,
                    onSelect: onNavSelect
                )
                .focusSection()
                // Nav is focusable ONLY while open. With it disabled when
                // closed, LEFT from the content edge can't reach it by
                // geometry — we open it explicitly (so LEFT from Watch can
                // choose page-prev vs open-nav). RIGHT returns to content.
                .disabled(!navOpen)
                .onMoveCommand { direction in
                    guard navOpen, direction == .right else { return }
                    navOpen = false
                    focus = lastContentFocus
                }
            }
            // The carousel's Watch/Continue button is the screen's initial
            // focus — stops the engine from auto-grabbing the nav on launch
            // (which would open it and trap focus there).
            .defaultFocus($focus, .heroWatch)
        }
    }

    // MARK: - Empty state (authorized but no entitlements)

    @FocusState private var emptyRefreshFocused: Bool

    private var emptyStateView: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 32) {
                Image(systemName: "film.slash")
                    .font(.system(size: 64))
                    .foregroundStyle(Theme.textDim)
                Text("Nothing here yet")
                    .font(.system(size: 40, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text("Your account doesn't have access to any content yet.\nContact your coach to get access.")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.textDim)
                    .multilineTextAlignment(.center)
                Button("Refresh") {
                    Task { await model.load(silent: false) }
                }
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(emptyRefreshFocused ? Theme.bg : Theme.gold)
                .padding(.horizontal, 48).padding(.vertical, 18)
                .background(emptyRefreshFocused ? Theme.gold : Theme.gold.opacity(0.18))
                .cornerRadius(12)
                .focused($emptyRefreshFocused)
                .buttonStyle(.plain)
            }
            .padding(80)
        }
        .onAppear { emptyRefreshFocused = true }
    }

    @ViewBuilder
    private var railsArea: some View {
        if model.rails.isEmpty {
            Spacer(minLength: 0)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                RailsView(
                    rails: model.rails,
                    focus: $focus,
                    onSelect: onSelectItem,
                    onUpFromFirstRail: bridgeUpToHero,
                    onLeftFromFirstColumn: openNav
                )
            }
        }
    }

    /// Backdrop source: spotlight art when collapsed (or in catalog), else
    /// the current carousel slide's backdrop.
    private var heroBackdropURL: URL? {
        let raw: String?
        if model.catalog != nil || !heroExpanded, let s = spotlight {
            raw = s.backdropUrl
        } else if !model.heroItems.isEmpty {
            let item = model.heroItems[min(slideIndex, model.heroItems.count - 1)]
            raw = item.backdropUrl ?? item.posterUrl
        } else {
            raw = nil
        }
        return ImageURL.sized(raw, width: 1920)
    }

    // MARK: - Focus reactions

    private func handleFocusChange(from old: HomeFocus?, to newValue: HomeFocus?) {
        switch newValue {
        case .card(let id):
            navOpen = false
            lastContentFocus = newValue!
            guard let pos = railPosition(for: id) else { break }
            let railId = model.rails[pos.railIndex].id

            // Did focus cross INTO this rail from a DIFFERENT rail (or the hero)?
            // Only then do we override the engine's geometric same-column landing
            // (§6.5). Moving LEFT/RIGHT within a rail must be left alone.
            let cameFromSameRail: Bool = {
                if case .card(let oldId) = old, let op = railPosition(for: oldId) {
                    return model.rails[op.railIndex].id == railId
                }
                return false
            }()

            if !cameFromSameRail {
                let remembered = visitedRails.contains(railId) ? (lastColumnByRail[railId] ?? 0) : 0
                let desired = min(remembered, model.rails[pos.railIndex].items.count - 1)
                if desired != pos.col {
                    // The engine landed on the wrong (same-as-previous) column.
                    // Re-assert the remembered/column-0 target on the next
                    // runloop so it wins; the corrected change finishes setup.
                    let targetId = model.rails[pos.railIndex].items[desired].id
                    DispatchQueue.main.async { focus = .card(targetId) }
                    return
                }
            }

            // Settled on the correct column — record it and drive the spotlight.
            visitedRails.insert(railId)
            lastColumnByRail[railId] = pos.col
            if let item = railItem(for: id) {
                spotlight = item.spotlight
                heroExpanded = false
            }
        case .heroWatch, .heroMyList, .heroInfo:
            navOpen = false
            lastContentFocus = newValue!
            if model.catalog == nil {
                heroExpanded = true
                spotlight = nil
            }
        case .detailDescription, .searchField, .searchClear:
            // Event Detail / Search-only focus targets; never occur on Home.
            // Listed to satisfy exhaustiveness over the shared focus space.
            break
        case .nav(let id):
            navOpen = true
            // Entering the nav from content lands on the nearest-by-geometry
            // item; snap it to the active section's item (Home on the home
            // screen) so the highlight always matches where we are.
            if !isNavFocus(old), id != activeNavId {
                DispatchQueue.main.async { focus = .nav(activeNavId) }
            }
        case .none:
            break
        }
    }

    private func isNavFocus(_ f: HomeFocus?) -> Bool {
        if case .nav = f { return true }
        return false
    }

    private func isHeroFocus(_ f: HomeFocus?) -> Bool {
        switch f {
        case .heroWatch, .heroMyList, .heroInfo: return true
        default: return false
        }
    }

    /// Silent, throttled Home refresh. Skips the spinner/focus reset (no
    /// `loading` toggle) and coalesces rapid triggers (path + scenePhase can
    /// both fire on one return) so we don't double-hit the API.
    private func refreshHome() {
        guard !model.loading else { return }
        guard Date().timeIntervalSince(lastRefresh) > 3 else { return }
        lastRefresh = Date()
        Task { await model.load(silent: true) }
    }

    private func setInitialFocus() {
        guard !didInitialFocus else { return }
        didInitialFocus = true
        DispatchQueue.main.async {
            // Clear nav-open first: if the engine grabbed the nav before this
            // ran, content is disabled and can't take focus until we re-enable.
            navOpen = false
            if !model.heroItems.isEmpty {
                focus = .heroWatch
            } else {
                focusFirstRailOrNav()
            }
        }
    }

    private func focusFirstRailOrNav() {
        DispatchQueue.main.async {
            if let first = model.rails.first?.items.first {
                focus = .card(first.id)
            } else {
                focus = .nav("home")
            }
        }
    }

    // MARK: - Helpers

    private var currentHeroEventId: Int? {
        guard !model.heroItems.isEmpty else { return nil }
        return model.heroItems[min(slideIndex, model.heroItems.count - 1)].id
    }
    private var currentHeroTitle: String? {
        guard !model.heroItems.isEmpty else { return nil }
        return model.heroItems[min(slideIndex, model.heroItems.count - 1)].title
    }

    private func railItem(for id: UUID) -> RailItem? {
        for rail in model.rails {
            if let item = rail.items.first(where: { $0.id == id }) { return item }
        }
        return nil
    }

    /// Locate a card's (rail index, column) within the current rails.
    private func railPosition(for id: UUID) -> (railIndex: Int, col: Int)? {
        for (ri, rail) in model.rails.enumerated() {
            if let ci = rail.items.firstIndex(where: { $0.id == id }) {
                return (ri, ci)
            }
        }
        return nil
    }

    private var activeNavId: String {
        switch model.catalog {
        case .meetups: return "meetups"
        case .livestreams: return "livestreams"
        case .continueWatching: return "continue"
        case .myList: return "mylist"
        case .none: return "home"
        }
    }

    // MARK: - Actions

    private func onNavSelect(_ id: String) {
        switch id {
        case "home":
            model.exitCatalog()
            heroExpanded = true
            spotlight = nil
            // Re-enable content before moving focus into it (content is
            // disabled while the nav holds focus).
            navOpen = false
            DispatchQueue.main.async { focus = model.heroItems.isEmpty ? focus : .heroWatch }
        case "search": router.push(.search)
        case "mynotes": router.push(.myNotes)
        case "settings": router.push(.settings)
        case "meetups": navOpen = false; model.enterCatalog(.meetups); focusFirstRailOrNav()
        case "livestreams": navOpen = false; model.enterCatalog(.livestreams); focusFirstRailOrNav()
        case "continue": navOpen = false; model.enterCatalog(.continueWatching); focusFirstRailOrNav()
        case "mylist": navOpen = false; model.enterCatalog(.myList); focusFirstRailOrNav()
        default: break
        }
    }

    /// LEFT past the Watch button: page to the previous slide if one exists,
    /// otherwise (on the first slide) open the nav (§6.4).
    private func heroLeftEdge() {
        guard model.catalog == nil else { openNav(); return }
        if slideIndex > 0 {
            slideForward = false   // LEFT pages backward → slide in from the leading edge
            withAnimation(.easeInOut(duration: 0.5)) { slideIndex -= 1 }
        } else {
            openNav()
        }
    }

    /// RIGHT past the Info button: page to the next slide (consume on the last).
    /// Landing focus on Watch/Continue mirrors the LEFT-edge behavior so every
    /// slide change parks on the primary CTA, not on whichever button paged.
    private func heroRightEdge() {
        guard model.catalog == nil, model.heroItems.count > 1 else { return }
        if slideIndex < model.heroItems.count - 1 {
            slideForward = true   // RIGHT pages forward → slide in from the trailing edge
            withAnimation(.easeInOut(duration: 0.5)) { slideIndex += 1 }
            focus = .heroWatch
        }
    }

    /// UP from the first rail → carousel Watch/Continue. The hero is COLLAPSED
    /// while a rail card is focused, and the action row (which contains the
    /// Watch button) is **only rendered in the expanded state**. So we must
    /// expand FIRST to mount the button, then move focus to it on the next
    /// runloop — focusing `.heroWatch` before it exists silently no-ops, which
    /// is why UP appeared to do nothing.
    private func bridgeUpToHero() {
        guard model.catalog == nil else { return }
        heroExpanded = true
        DispatchQueue.main.async { focus = .heroWatch }
    }

    /// Open the nav and land focus on the active section's item. The nav is
    /// disabled while closed, so this explicit move is the only way in.
    private func openNav() {
        navOpen = true
        DispatchQueue.main.async { focus = .nav(activeNavId) }
    }

    private func onSelectItem(_ item: RailItem) {
        if let videoId = item.videoId {
            router.push(.player(videoId: videoId))
        } else if let eventId = item.eventId {
            router.push(.eventDetail(id: eventId, title: item.eventTitle))
        }
    }
}
