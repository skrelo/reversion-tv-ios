import SwiftUI

/// Full-bleed hero backdrop. Drawn as a background BEHIND the nav + content
/// so the image stays edge-to-edge while the nav/content stay cleanly
/// adjacent for the focus engine (§6.3). Keeps the last image until the
/// next loads via the `.id`/opacity transition.
struct HeroBackdropView: View {
    let url: URL?
    /// Carousel paging direction (true = forward/next). Drives which edge the
    /// new backdrop slides in from.
    var slideForward: Bool = true
    /// When true the backdrop SLIDES (carousel paging, §6.2 — matches the other
    /// OSs); when false it crossfades (spotlight art swap while arrowing rails).
    var sliding: Bool = false

    private var transition: AnyTransition {
        guard sliding else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: slideForward ? .trailing : .leading),
            removal: .move(edge: slideForward ? .leading : .trailing))
    }

    var body: some View {
        ZStack {
            Theme.bg
            RemoteImage(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .id(url?.absoluteString ?? "none")
                .transition(transition)
            // Bottom scrim only — for hero text legibility. The hero runs
            // FULL-BLEED left↔right; there is NO left scrim. Any left-edge
            // darkening comes solely from the nav's own gradient, and ONLY
            // while the nav is open (§6.6).
            LinearGradient(colors: [.clear, Theme.bg.opacity(0.25), Theme.bg.opacity(0.96), Theme.bg],
                           startPoint: .top, endPoint: .bottom)
        }
    }
}

/// Hero content (§6.2 / §6.3) — transparent; sits in the content column to
/// the RIGHT of the nav, over the backdrop. Expanded = carousel text + the
/// 3-item action row + dots; collapsed = spotlight text (no action row).
struct HeroContentView: View {
    let heroItems: [MediaItem]
    let slideIndex: Int
    let spotlight: SpotlightData?
    let expanded: Bool
    let isInMyList: Bool
    /// Carousel paging direction (true = forward/next) — sets which edge the
    /// wordmark/text slide in from. Ignored in spotlight mode (crossfade).
    var slideForward: Bool = true
    @FocusState.Binding var focus: HomeFocus?

    let onPlay: (Int) -> Void
    let onInfo: (Int) -> Void
    let onToggleMyList: (Int) -> Void
    /// LEFT past the leftmost button (Watch): page the previous slide, or open
    /// the nav when already on the first slide (§6.4). RIGHT past the rightmost
    /// button (Info): page the next slide. Both fire ONLY at the edge — moving
    /// *onto* a button never pages, so Info stays selectable to open detail.
    let onLeftEdge: () -> Void
    let onRightEdge: () -> Void

    private var current: MediaItem? {
        guard !heroItems.isEmpty else { return nil }
        return heroItems[min(slideIndex, heroItems.count - 1)]
    }

    /// Identity for the crossfading text block — changes per carousel slide
    /// (expanded) or per spotlight (collapsed), so the slide text dissolves
    /// like a slideshow while the action row below stays put.
    private var slideKey: String {
        if expanded { return "carousel-\(slideIndex)" }
        return "spot-\(spotlight?.title ?? "")-\(spotlight?.videoTitle ?? "")"
    }

    /// Carousel pages with a horizontal SLIDE (§6.2 — matches Android/Tizen):
    /// the new slide enters from the trailing edge going forward (leading going
    /// back) while the old one exits the opposite side. Spotlight (collapsed)
    /// keeps a crossfade — it's a focus-driven art swap, not a carousel page.
    private var slideTransition: AnyTransition {
        guard expanded else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: slideForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: slideForward ? .leading : .trailing).combined(with: .opacity))
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear

            // CAROUSEL wordmark — top-CENTER, its own band, NOT grouped with the
            // bottom meta/action column (matches Android: 9-grid default
            // `top_center`, sized ~620×190dp; meta + actions sit bottom-left
            // separately). Crossfades per slide. Only shown in carousel mode when
            // the event actually has a wordmark; otherwise the title text renders
            // in the bottom column (see `carouselContent`).
            if expanded, let event = current, let w = event.wordmarkUrl, !w.isEmpty {
                carouselWordmark(w)
                    .id("wm-\(slideIndex)")
                    .transition(slideTransition)
            }

            // Slide TEXT — crossfades per slide (slideshow). No action row here,
            // so the focused button isn't recreated mid-transition.
            content
                .id(slideKey)
                .transition(slideTransition)
                .padding(.leading, 60)
                .padding(.trailing, 120)
                // Lifts the meta/text UP off the action row (carousel) / first
                // rail header (spotlight). On the carousel the action row top
                // sits ~112 pt off the bottom (36 pad + 76 button), so this must
                // clear that with breathing room between the description and the
                // buttons (matches Android/Tizen spacing).
                .padding(.bottom, expanded ? 168 : 88)

            // Action row — STABLE across slides (not keyed), so focus survives
            // paging. It reads the current event, so its label/targets update
            // in place.
            if expanded, let event = current {
                actionRow(event)
                    .padding(.leading, 60)
                    .padding(.bottom, 36)
            }

            if expanded, heroItems.count > 1 {
                dots.frame(maxWidth: .infinity, alignment: .center).padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        // Clip to the hero region so a crossfading backdrop/text can't bleed
        // down behind the rails during a slide transition.
        .clipped()
    }

    /// Carousel wordmark, pinned TOP-CENTER (Android default `top_center`).
    /// Capped to the carousel size (~620×190dp ≈ 1180×320pt at tvOS 1080p
    /// points) with aspect preserved — wide marks cap on width, stacked marks
    /// cap on height.
    private func carouselWordmark(_ w: String) -> some View {
        VStack(spacing: 0) {
            RemoteImage(url: ImageURL.sized(w, width: ImageURL.wordmarkWidth), contentMode: .fit)
                .frame(maxWidth: 1180, maxHeight: 320, alignment: .center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 60)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    @ViewBuilder
    private var content: some View {
        if !expanded, let s = spotlight {
            spotlightContent(s)
        } else if let event = current {
            carouselContent(event)
        }
    }

    private func spotlightContent(_ s: SpotlightData) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            titleOrWordmark(wordmark: s.wordmarkUrl, title: s.title)
            if let vt = s.videoTitle, !vt.isEmpty {
                Text(vt).font(.system(size: 28, weight: .semibold)).foregroundStyle(Theme.text)
            }
            metaLine(date: s.sessionDate, videoCount: s.videoCount)
            tagline(s.tagline)
            description(Html.strip(s.description), lines: 2)
        }
        .frame(maxWidth: 1100, alignment: .leading)
    }

    private func carouselContent(_ event: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            // No-wordmark fallback: serif title in the bottom-left column (the
            // wordmark, when present, renders separately top-center).
            if (event.wordmarkUrl ?? "").isEmpty {
                Text(event.title ?? "")
                    .font(.system(size: 60, weight: .heavy, design: .serif))
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
            }
            metaLine(date: event.sessionDate, videoCount: event.videoCount ?? 0)
            tagline(event.tvSubtitle)
            description(Html.strip(event.shortDescription), lines: 3)
        }
        .frame(maxWidth: 1100, alignment: .leading)
    }

    private func actionRow(_ event: MediaItem) -> some View {
        HStack(spacing: 24) {
            // Watch / Continue — leftmost, default focus (§6.4).
            Button(action: {
                if let vid = event.watchTarget?.id { onPlay(vid) }
                else if let id = event.id { onInfo(id) }
            }) {
                HStack(spacing: 14) {
                    Image(systemName: "play.fill").font(.system(size: 26, weight: .bold))
                    Text(event.watchTarget != nil ? event.watchLabel : "View")
                        .font(.system(size: 28, weight: .bold))
                }
                .padding(.horizontal, 40)
                .frame(height: 76)
            }
            .buttonStyle(HeroPillButtonStyle())
            .focused($focus, equals: .heroWatch)
            .onMoveCommand { if $0 == .left { onLeftEdge() } }

            Button(action: { if let id = event.id { onToggleMyList(id) } }) {
                Image(systemName: isInMyList ? "checkmark" : "plus")
                    .font(.system(size: 30, weight: .bold))
                    .frame(width: 76, height: 76)
            }
            .buttonStyle(HeroIconButtonStyle())
            .focused($focus, equals: .heroMyList)

            Button(action: { if let id = event.id { onInfo(id) } }) {
                Image(systemName: "info.circle")
                    .font(.system(size: 30, weight: .bold))
                    .frame(width: 76, height: 76)
            }
            .buttonStyle(HeroIconButtonStyle())
            .focused($focus, equals: .heroInfo)
            .onMoveCommand { if $0 == .right { onRightEdge() } }
        }
    }

    private var dots: some View {
        HStack(spacing: 12) {
            ForEach(0..<heroItems.count, id: \.self) { i in
                Circle()
                    .fill(i == slideIndex ? Theme.gold : Theme.textDim.opacity(0.5))
                    .frame(width: 12, height: 12)
            }
        }
    }

    // MARK: Shared bits

    @ViewBuilder
    private func titleOrWordmark(wordmark: String?, title: String) -> some View {
        if let w = wordmark, !w.isEmpty {
            // Spotlight (collapsed) wordmark — left-aligned in the content
            // column, sized SMALLER than the carousel mark (Android spotlight
            // cap ~340×110dp ≈ 680×220pt) so it reads as a header above the
            // meta/description, not a full takeover.
            RemoteImage(url: ImageURL.sized(w, width: ImageURL.wordmarkWidth), contentMode: .fit)
                .frame(maxWidth: 680, maxHeight: 220, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(title)
                .font(.system(size: 60, weight: .heavy, design: .serif))
                .foregroundStyle(Theme.text)
                .lineLimit(2)
        }
    }

    @ViewBuilder
    private func metaLine(date: String?, videoCount: Int) -> some View {
        let countLabel = videoCount > 0 ? "\(videoCount) video\(videoCount == 1 ? "" : "s")" : ""
        if (date?.isEmpty == false) || !countLabel.isEmpty {
            HStack(spacing: 12) {
                if let date, !date.isEmpty { Text(date) }
                if let date, !date.isEmpty, !countLabel.isEmpty { Text("·") }
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

    @ViewBuilder
    private func tagline(_ text: String?) -> some View {
        if let text, !text.isEmpty {
            Text(text).font(.system(size: 26, weight: .semibold)).foregroundStyle(Theme.gold)
        }
    }

    @ViewBuilder
    private func description(_ text: String?, lines: Int) -> some View {
        if let text, !text.isEmpty {
            Text(text)
                .font(.system(size: 24))
                .foregroundStyle(Theme.text.opacity(0.9))
                .lineLimit(lines)
                .frame(maxWidth: 980, alignment: .leading)
        }
    }
}

// MARK: - Button styles

struct HeroPillButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isFocused ? Theme.bg : Theme.text)
            .background(Capsule().fill(isFocused ? Theme.gold : Color.white.opacity(0.16)))
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}

struct HeroIconButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // Icon buttons (My List / Info) go WHITE on focus — only the
            // Watch/Continue pill uses gold (§6.4).
            .foregroundStyle(isFocused ? Theme.bg : Theme.text)
            .background(Circle().fill(isFocused ? Color.white : Color.white.opacity(0.16)))
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
