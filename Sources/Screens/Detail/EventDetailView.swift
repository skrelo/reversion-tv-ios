import SwiftUI

/// Event Detail (§7). Paramount-style fixed hero (backdrop + two columns:
/// wordmark/title + action row on the left, tagline + clamped description +
/// meta on the right) above a single "Videos" rail. Left nav present with Home
/// active; selecting any nav item returns Home. Reuses the shared `LeftNavView`,
/// `RailsView`/`CardView`, and hero button styles.
struct EventDetailView: View {
    @EnvironmentObject private var router: AppRouter
    let eventId: Int
    let fallbackTitle: String?

    @StateObject private var vm: EventDetailViewModel
    @FocusState private var focus: HomeFocus?
    @State private var navOpen = false
    @State private var lastContentFocus: HomeFocus = .heroWatch
    @State private var showFullDescription = false
    @State private var didInitialFocus = false

    // Sized so the hero + the single Videos rail (title + one card row) both fit
    // on screen without the rail needing to scroll up — which is what clipped
    // the "Videos" header on DOWN (§7).
    private let heroHeight: CGFloat = 600

    init(eventId: Int, title: String?) {
        self.eventId = eventId
        self.fallbackTitle = title
        _vm = StateObject(wrappedValue: EventDetailViewModel(eventId: eventId))
    }

    var body: some View {
        content
            .task { await vm.load() }
            .onChange(of: vm.loading) { _, isLoading in if !isLoading { setInitialFocus() } }
            .onChange(of: focus) { _, newValue in
                if let f = newValue, !isNavFocus(f) { lastContentFocus = f; navOpen = false }
            }
            // BACK closes the full-description modal first; otherwise the
            // NavigationStack pops the screen as usual.
            .onExitCommand {
                if showFullDescription { showFullDescription = false }
                else if !router.path.isEmpty { router.path.removeLast() }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let error = vm.error {
            ZStack { Theme.bg.ignoresSafeArea()
                Text(error).font(.system(size: 30)).foregroundStyle(Theme.textDim) }
        } else if vm.loading || vm.event == nil {
            ZStack { Theme.bg.ignoresSafeArea(); ProgressView().scaleEffect(2) }
        } else {
            ZStack(alignment: .topLeading) {
                Theme.bg.ignoresSafeArea()

                HeroBackdropView(url: ImageURL.sized(vm.event?.backdropUrl ?? vm.event?.posterUrl, width: 1920))
                    .frame(height: heroHeight)
                    .clipped()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 0) {
                    hero
                        .frame(height: heroHeight)
                        .focusSection()
                    railsArea
                        .focusSection()
                }
                .padding(.leading, LeftNavView.stripWidth)
                .disabled(navOpen)

                LeftNavView(
                    activeId: "home",
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

                if showFullDescription {
                    fullDescriptionModal
                }
            }
            .defaultFocus($focus, .heroWatch)
        }
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        if let event = vm.event {
            ZStack(alignment: .top) {
                // Wordmark TOP-CENTER, same treatment as the home carousel.
                heroWordmark(event)
                    .padding(.top, 60)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Bottom two columns: action row (left) + tagline/description/
                // meta (right), bottom-aligned so the meta line and the action
                // row sit on the same band.
                HStack(alignment: .bottom, spacing: 40) {
                    actionRow(event)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    rightColumn(event)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.leading, 60)
                .padding(.trailing, 80)
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
    }

    @ViewBuilder
    private func heroWordmark(_ event: MediaItem) -> some View {
        if let w = event.wordmarkUrl, !w.isEmpty {
            RemoteImage(url: ImageURL.sized(w, width: ImageURL.wordmarkWidth), contentMode: .fit)
                .frame(maxWidth: 1180, maxHeight: 300, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(event.title ?? fallbackTitle ?? "")
                .font(.system(size: 58, weight: .heavy, design: .serif))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
    }

    private func actionRow(_ event: MediaItem) -> some View {
        HStack(spacing: 24) {
            Button(action: {
                if let vid = vm.watchTarget?.id { router.push(.player(videoId: vid)) }
            }) {
                HStack(spacing: 14) {
                    Image(systemName: "play.fill").font(.system(size: 26, weight: .bold))
                    Text(vm.watchLabel).font(.system(size: 28, weight: .bold))
                }
                .padding(.horizontal, 40)
                .frame(height: 76)
            }
            .buttonStyle(HeroPillButtonStyle())
            .focused($focus, equals: .heroWatch)
            .disabled(vm.watchTarget == nil)
            .opacity(vm.watchTarget == nil ? 0.5 : 1)
            .onMoveCommand { if $0 == .left { openNav() } }

            Button(action: { vm.toggleBookmark() }) {
                Image(systemName: vm.isBookmarked ? "checkmark" : "plus")
                    .font(.system(size: 30, weight: .bold))
                    .frame(width: 76, height: 76)
            }
            .buttonStyle(HeroIconButtonStyle())
            .focused($focus, equals: .heroMyList)
        }
    }

    @ViewBuilder
    private func rightColumn(_ event: MediaItem) -> some View {
        let desc = Html.strip(event.description ?? event.shortDescription)
        VStack(alignment: .leading, spacing: 14) {
            if let tag = event.tvSubtitle, !tag.isEmpty {
                Text(tag).font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.gold).lineLimit(2)
                    // Match the description block's inner inset so the tagline,
                    // description text, and meta all share one left edge.
                    .padding(.leading, Self.descInset)
            }
            if !desc.isEmpty {
                Button(action: { showFullDescription = true }) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(desc)
                            .font(.system(size: 24))
                            .foregroundStyle(Theme.text.opacity(0.95))
                            .lineLimit(5)
                            .multilineTextAlignment(.leading)
                        HStack(spacing: 4) {
                            Text("More").font(.system(size: 20, weight: .bold))
                            Image(systemName: "chevron.right").font(.system(size: 16, weight: .bold))
                        }
                        .foregroundStyle(Theme.textDim)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(DescriptionBlockButtonStyle())
                .focused($focus, equals: .detailDescription)
            }
            metaLine(event)
                .padding(.leading, Self.descInset)
        }
    }

    /// Shared left inset for the right-column text so the description block's
    /// focus padding doesn't push its text out of line with the tagline/meta.
    private static let descInset: CGFloat = 18

    @ViewBuilder
    private func metaLine(_ event: MediaItem) -> some View {
        let count = event.videoCount ?? 0
        let countLabel = count > 0 ? "\(count) video\(count == 1 ? "" : "s")" : ""
        let date = event.sessionDate ?? ""
        if !date.isEmpty || !countLabel.isEmpty {
            HStack(spacing: 12) {
                if !date.isEmpty { Text(date) }
                if !date.isEmpty, !countLabel.isEmpty { Text("·") }
                if !countLabel.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "video.fill").font(.system(size: 18))
                        Text(countLabel)
                    }
                }
            }
            .font(.system(size: 22, weight: .medium))
            .foregroundStyle(Theme.gold)
        }
    }

    // MARK: - Videos rail

    @ViewBuilder
    private var railsArea: some View {
        if vm.videoRails.isEmpty {
            Text("No videos yet.")
                .font(.system(size: 26)).foregroundStyle(Theme.textDim)
                .padding(.leading, 60).padding(.top, 40)
            Spacer(minLength: 0)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                RailsView(
                    rails: vm.videoRails,
                    focus: $focus,
                    onSelect: { item in if let vid = item.videoId { router.push(.player(videoId: vid)) } },
                    onUpFromFirstRail: { focus = .heroWatch },
                    onLeftFromFirstColumn: openNav,
                    cardsShowArtTitle: false,
                    bottomInset: 40
                )
            }
        }
    }

    // MARK: - Full-description modal

    private var fullDescriptionModal: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(vm.event?.title ?? fallbackTitle ?? "")
                        .font(.system(size: 40, weight: .bold))
                        .foregroundStyle(Theme.text)
                    Text(Html.strip(vm.event?.description ?? vm.event?.shortDescription))
                        .font(.system(size: 26))
                        .foregroundStyle(Theme.text.opacity(0.92))
                        .lineSpacing(8)
                }
                .frame(maxWidth: 1200, alignment: .leading)
                .padding(60)
            }
            .background(RoundedRectangle(cornerRadius: 24).fill(Theme.bg))
            .frame(maxWidth: 1320, maxHeight: 820)
        }
        .transition(.opacity)
    }

    // MARK: - Focus / nav

    private func setInitialFocus() {
        guard !didInitialFocus, vm.event != nil else { return }
        didInitialFocus = true
        DispatchQueue.main.async {
            navOpen = false
            focus = vm.watchTarget != nil ? .heroWatch : .detailDescription
        }
    }

    private func isNavFocus(_ f: HomeFocus?) -> Bool {
        if case .nav = f { return true }
        return false
    }

    private func openNav() {
        navOpen = true
        DispatchQueue.main.async { focus = .nav("home") }
    }

    /// Selecting ANY nav item returns Home (§7). Search / Settings push their
    /// own screens on top; everything else pops back to the Home root.
    private func onNavSelect(_ id: String) {
        switch id {
        case "search": router.push(.search)
        case "settings": router.push(.settings)
        default: router.popToRoot()
        }
    }
}

/// Focusable long-description block: subtle rounded background that brightens
/// on focus, no default tvOS button chrome (§7).
struct DescriptionBlockButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? Color.white.opacity(0.12) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(Theme.gold, lineWidth: isFocused ? 3 : 0)
            )
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
