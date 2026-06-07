import SwiftUI

/// Full-bleed hero backdrop. Drawn as a background BEHIND the nav + content
/// so the image stays edge-to-edge while the nav/content stay cleanly
/// adjacent for the focus engine (§6.3). Keeps the last image until the
/// next loads via the `.id`/opacity transition.
struct HeroBackdropView: View {
    let url: URL?

    var body: some View {
        ZStack {
            Theme.bg
            RemoteImage(url: url)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .id(url?.absoluteString ?? "none")
                .transition(.opacity)
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
    @FocusState.Binding var focus: HomeFocus?

    let onPlay: (Int) -> Void
    let onInfo: (Int) -> Void
    let onToggleMyList: (Int) -> Void

    private var current: MediaItem? {
        guard !heroItems.isEmpty else { return nil }
        return heroItems[min(slideIndex, heroItems.count - 1)]
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            content
                .padding(.leading, 60)
                .padding(.trailing, 120)
                // Lifts the wordmark/meta UP off the first rail header so there's
                // clear breathing room between the spotlight and "Continue
                // Watching" (matches Android/Tizen spacing).
                .padding(.bottom, 88)
            if expanded, heroItems.count > 1 {
                dots.frame(maxWidth: .infinity, alignment: .center).padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
            titleOrWordmark(wordmark: event.wordmarkUrl, title: event.title ?? "")
            metaLine(date: event.sessionDate, videoCount: event.videoCount ?? 0)
            tagline(event.tvSubtitle)
            description(Html.strip(event.shortDescription), lines: 3)
            actionRow(event).padding(.top, 12)
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
            RemoteImage(url: ImageURL.sized(w, width: ImageURL.wordmarkWidth), contentMode: .fit)
                .frame(maxWidth: 720, maxHeight: 180, alignment: .leading)
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
            .foregroundStyle(isFocused ? Theme.bg : Theme.text)
            .background(Circle().fill(isFocused ? Theme.gold : Color.white.opacity(0.16)))
            .scaleEffect(isFocused ? 1.06 : 1.0)
            .animation(.easeOut(duration: 0.15), value: isFocused)
    }
}
