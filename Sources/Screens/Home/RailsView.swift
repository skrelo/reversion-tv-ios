import SwiftUI

/// Vertical list of horizontal rails (§6.5). tvOS's focus engine handles
/// vertical scroll-to-rail and horizontal scroll-to-card; focusing a card
/// drives the spotlight via the shared `focus` binding.
struct RailsView: View {
    let rails: [HomeRail]
    @FocusState.Binding var focus: HomeFocus?
    let onSelect: (RailItem) -> Void
    /// UP from a card in the FIRST rail bridges back to the hero (the vertical
    /// scroll view otherwise swallows UP at its top edge). Handled on the
    /// focused card itself — the deepest responder — so it fires before the
    /// scroll view can eat the press.
    var onUpFromFirstRail: (() -> Void)? = nil

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 44) {
            ForEach(Array(rails.enumerated()), id: \.element.id) { index, rail in
                VStack(alignment: .leading, spacing: 12) {
                    Text(rail.title)
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.text)
                        .padding(.leading, 60)
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 28) {
                            ForEach(rail.items) { item in
                                CardView(
                                    item: item,
                                    focus: $focus,
                                    onSelect: { onSelect(item) },
                                    onMoveUp: index == 0 ? onUpFromFirstRail : nil
                                )
                            }
                        }
                        .padding(.horizontal, 60)
                        // Room for the 1.1× focus pop so it never clips.
                        .padding(.vertical, 28)
                    }
                }
                // Each rail is its own focus section so the engine restores
                // the last-focused card when you move DOWN then back UP onto
                // it (settled-column memory, §6.5).
                .focusSection()
            }
        }
        // Headroom so the FIRST rail's title isn't clipped under the hero
        // when the rails auto-scroll to keep a focused card visible.
        .padding(.top, 72)
        .padding(.bottom, 80)
    }
}

/// Card focus visuals only — scale, no system "card" chrome (the default
/// tvOS button style draws the white floating panel we don't want).
struct CardButtonStyle: ButtonStyle {
    @Environment(\.isFocused) private var isFocused
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(isFocused ? 1.1 : 1.0)
            .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}

struct CardView: View {
    let item: RailItem
    @FocusState.Binding var focus: HomeFocus?
    let onSelect: () -> Void
    var onMoveUp: (() -> Void)? = nil

    private var isFocused: Bool { focus == .card(item.id) }

    private var artURL: URL? {
        ImageURL.sized(item.media.cardPosterUrl ?? item.media.coverUrl ?? item.media.posterUrl,
                       width: ImageURL.cardWidth)
    }
    private var hasBakedPoster: Bool { (item.media.cardPosterUrl?.isEmpty == false) }
    private var wordmarkURL: URL? {
        ImageURL.sized(item.media.wordmarkUrl ?? item.media.eventWordmarkUrl, width: ImageURL.cardWidth)
    }
    private var overlayTitle: String {
        guard !hasBakedPoster, wordmarkURL == nil else { return "" }
        return item.isVideo ? item.media.resolvedEventTitle : (item.media.title ?? "")
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                art
                belowText
            }
        }
        .buttonStyle(CardButtonStyle())
        .focused($focus, equals: .card(item.id))
        .onMoveCommand { direction in
            if direction == .up, let onMoveUp { onMoveUp() }
        }
    }

    private var art: some View {
        ZStack(alignment: .bottom) {
            RemoteImage(url: artURL)
                .frame(width: 360, height: 202)
                .clipped()

            if !hasBakedPoster {
                LinearGradient(colors: [.clear, .black.opacity(0.7)],
                               startPoint: .center, endPoint: .bottom)
            }
            if let wm = wordmarkURL, !hasBakedPoster {
                RemoteImage(url: wm, contentMode: .fit)
                    .frame(maxWidth: 280, maxHeight: 70)
                    .padding(.bottom, 12)
            } else if !overlayTitle.isEmpty {
                Text(overlayTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(8)
            }

            if item.isContinueWatching {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Badges (top-left).
            VStack { HStack { badge; Spacer() }; Spacer() }
                .padding(8)

            if item.progressFraction > 0 {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.white.opacity(0.25))
                        Rectangle().fill(Theme.progress)
                            .frame(width: geo.size.width * item.progressFraction)
                    }
                }
                .frame(height: 6)
            }
        }
        .frame(width: 360, height: 202)
        .overlay(
            Rectangle()
                .strokeBorder(Theme.gold, lineWidth: isFocused ? 5 : 0)
        )
    }

    @ViewBuilder
    private var badge: some View {
        if item.media.isNew == true {
            chip("NEW", bg: Theme.gold, fg: Theme.bg)
        } else if let b = item.bookmarkBadge {
            chip(b, bg: .black.opacity(0.65), fg: .white)
        }
    }

    private func chip(_ text: String, bg: Color, fg: Color) -> some View {
        Text(text)
            .font(.system(size: 14, weight: .heavy))
            .foregroundStyle(fg)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(bg)
    }

    @ViewBuilder
    private var belowText: some View {
        let title = item.isVideo ? (item.media.title ?? "") : ""
        let meta = item.media.sessionDate ?? item.media.videoDate ?? ""
        if !title.isEmpty || !meta.isEmpty {
            VStack(alignment: .leading, spacing: 2) {
                if !title.isEmpty {
                    Text(title).font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Theme.text).lineLimit(1)
                }
                if !meta.isEmpty {
                    Text(meta).font(.system(size: 18)).foregroundStyle(Theme.textDim).lineLimit(1)
                }
            }
            .frame(width: 360, alignment: .leading)
        }
    }
}
