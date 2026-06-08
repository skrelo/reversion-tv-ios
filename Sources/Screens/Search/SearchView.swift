import SwiftUI

/// Search (§8). Left nav (Search active) + a query bar with a native tvOS
/// `TextField` and an Events/Videos result area below. Focusing the field opens
/// the system keyboard, which carries **dictation** — that is the tvOS voice /
/// speech-to-text path (§8 requires voice on every platform; no custom on-screen
/// keyboard is needed). Reuses the shared `LeftNavView` and `RailsView`/`CardView`.
struct SearchView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = SearchViewModel()
    @FocusState private var focus: HomeFocus?
    @State private var navOpen = false
    @State private var lastContentFocus: HomeFocus = .searchField
    @State private var didInitialFocus = false
    /// Focus scope for the results so DOWN off the query bar lands on card 0
    /// directly (the first card is the scope's default focus), avoiding the
    /// geometric-nearest-then-snap flicker (§8).
    @Namespace private var resultsNS

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 28) {
                queryBar
                    .focusSection()
                resultsArea
                    .focusSection()
            }
            .padding(.top, 60)
            .padding(.leading, LeftNavView.stripWidth)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .disabled(navOpen)

            LeftNavView(
                activeId: "search",
                profileName: vm.profileName,
                profileHandle: vm.profileHandle,
                focus: $focus,
                onSelect: onNavSelect
            )
            .focusSection()
            .disabled(!navOpen)
            .onMoveCommand { direction in
                guard navOpen, direction == .right else { return }
                navOpen = false
                focus = lastContentFocus
            }
        }
        .defaultFocus($focus, .searchField)
        .task { await vm.loadProfile() }
        .onAppear { setInitialFocus() }
        .onChange(of: focus) { _, newValue in
            if let f = newValue, !isNavFocus(f) { lastContentFocus = f; navOpen = false }
        }
        .onChange(of: vm.query) { _, _ in vm.onQueryChanged() }
        // BACK closes the nav first if open; otherwise pops the screen.
        .onExitCommand {
            if navOpen { navOpen = false; focus = lastContentFocus }
            else if !router.path.isEmpty { router.path.removeLast() }
        }
    }

    // MARK: - Query bar

    private var queryBar: some View {
        HStack(spacing: 22) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(Theme.textDim)

            TextField(text: $vm.query) {
                Text("Search events & videos").foregroundStyle(Theme.textDim)
            }
            .textFieldStyle(.plain)
            .font(.system(size: 36))
            .foregroundStyle(Theme.text)
            .focused($focus, equals: .searchField)
            // LEFT opens the nav; DOWN is handled by the results' focus scope
            // (prefersDefaultFocus on card 0), not a manual override.
            .onMoveCommand { direction in
                if direction == .left { openNav() }
            }

            if !vm.query.isEmpty {
                Button(action: { vm.query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 32))
                }
                .buttonStyle(ClearButtonStyle())
                .focused($focus, equals: .searchClear)
                .onMoveCommand { direction in
                    if direction == .left { focus = .searchField }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 22)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Theme.gold, lineWidth: focus == .searchField ? 4 : 0)
                )
        )
        .padding(.trailing, 80)
    }

    // MARK: - Results

    @ViewBuilder
    private var resultsArea: some View {
        switch vm.status {
        case .prompt:
            message("Type at least 2 characters to search.")
        case .loading:
            ProgressView()
                .scaleEffect(1.8)
                .tint(Theme.text)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .error:
            message("Search failed. Try again.")
        case .empty:
            message("No results for \u{201C}\(vm.query.trimmingCharacters(in: .whitespacesAndNewlines))\u{201D}.")
        case .results:
            ScrollView(.vertical, showsIndicators: false) {
                RailsView(
                    rails: vm.rails,
                    focus: $focus,
                    onSelect: onSelectItem,
                    onUpFromFirstRail: { focus = .searchField },
                    onLeftFromFirstColumn: openNav,
                    cardsShowArtTitle: true,
                    bottomInset: 80,
                    defaultFocusNamespace: resultsNS
                )
            }
            .focusScope(resultsNS)
        }
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 28))
            .foregroundStyle(Theme.textDim)
            .padding(.leading, 60)
            .padding(.top, 40)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Focus / nav

    private func setInitialFocus() {
        guard !didInitialFocus else { return }
        didInitialFocus = true
        DispatchQueue.main.async {
            navOpen = false
            focus = .searchField
        }
    }

    private func isNavFocus(_ f: HomeFocus?) -> Bool {
        if case .nav = f { return true }
        return false
    }

    private func openNav() {
        navOpen = true
        DispatchQueue.main.async { focus = .nav("search") }
    }

    private func onSelectItem(_ item: RailItem) {
        if let vid = item.videoId { router.push(.player(videoId: vid)); return }
        if let eid = item.eventId { router.push(.eventDetail(id: eid, title: item.eventTitle)) }
    }

    /// Selecting a nav item: Home/Meetups/etc. pop to the Home root; Settings
    /// pushes on top; Search just closes the nav (already here).
    private func onNavSelect(_ id: String) {
        switch id {
        case "search":
            navOpen = false
            focus = .searchField
        case "settings":
            router.push(.settings)
        default:
            router.popToRoot()
        }
    }
}

/// Strips the default tvOS button chrome on the clear button so only the glyph
/// shows; it brightens on focus.
struct ClearButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused ? Theme.gold : Theme.textDim)
            .scaleEffect(isFocused ? 1.15 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
