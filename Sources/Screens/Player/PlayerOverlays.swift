import SwiftUI

/// Marker accent colors (§9.6): coach annotations = gold, private notes = sky.
enum MarkerColor {
    static let annotation = Theme.gold
    static let note = Color(red: 0x4E / 255, green: 0xA8 / 255, blue: 0xE8 / 255)

    static func dot(_ kind: Marker.Kind) -> Color {
        kind == .note ? note : annotation
    }
}

/// On-device QR image (navy on white) for a string (§9.7/§9.8).
struct ScanQR: View {
    let string: String
    var size: CGFloat = 256

    var body: some View {
        if let img = QRCodeGenerator.image(from: string, size: size * 2) {
            Image(uiImage: img)
                .resizable()
                .interpolation(.none)
                .frame(width: size, height: size)
                .background(Color.white)
                .cornerRadius(8)
        } else {
            Color.white.frame(width: size, height: size).cornerRadius(8)
        }
    }
}

// MARK: - Markers strip (§9.6)

struct MarkerStripView: View {
    let markers: [Marker]
    let focused: Bool
    let focusIndex: Int
    let playheadIndex: Int?
    let centerNonce: Int

    var body: some View {
        if markers.isEmpty { EmptyView() } else {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 16) {
                        ForEach(Array(markers.enumerated()), id: \.element.key) { i, m in
                            chip(m, focused: focused && i == focusIndex).id(i)
                        }
                    }
                    .padding(.horizontal, 80)
                }
                .frame(height: 116)
                // Fade chips in/out at the strip edges so the chips that scroll
                // past the chrome margin don't hard-slice against the full-bleed
                // video — reads as an intentional carousel rather than a cut.
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.035),
                            .init(color: .black, location: 0.965),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .onChange(of: focusIndex) { _, idx in
                    if focused { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(idx, anchor: .center) } }
                }
                // Auto-center on the chip nearest the playhead: when the chrome
                // opens (centerNonce), when the nearest marker changes (e.g. the
                // resume seed lands after load), and on first appear. Never while
                // the strip is focused (§9.6). Dispatched async + instant so it
                // isn't skipped when the strip is still opacity-0 at fire time.
                .onChange(of: centerNonce) { _, _ in center(proxy) }
                .onChange(of: playheadIndex) { _, _ in center(proxy) }
                .onAppear { center(proxy) }
            }
        }
    }

    /// Instant-center on the chip nearest the playhead (never while focused).
    /// Async so it runs after the current layout/opacity pass — a smooth or
    /// same-pass scroll on a still-hidden strip gets skipped, leaving it at 0.
    private func center(_ proxy: ScrollViewProxy) {
        guard !focused, let p = playheadIndex else { return }
        DispatchQueue.main.async { proxy.scrollTo(p, anchor: .center) }
    }

    private func chip(_ m: Marker, focused: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(MarkerColor.dot(m.kind)).frame(width: 14, height: 14).padding(.top, 6)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(Html.timecode(m.startsAt))
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MarkerColor.dot(m.kind))
                    Text(m.title.isEmpty ? (m.isNote ? "Note" : "Annotation") : m.title)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                }
                Text(m.bodyText.isEmpty ? " " : m.bodyText)
                    .font(.system(size: 20))
                    .foregroundStyle(Theme.textDim)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 20)
        .frame(width: 460, height: 92, alignment: .leading)
        .background(focused ? Theme.text.opacity(0.16) : Color.black.opacity(0.45))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .stroke(focused ? MarkerColor.dot(m.kind) : Color.white.opacity(0.12), lineWidth: focused ? 3 : 1))
        .cornerRadius(12)
        .scaleEffect(focused ? 1.04 : 1)
        .animation(.easeOut(duration: 0.15), value: focused)
    }
}

// MARK: - Ambient auto pop-up (§9.6)

struct MarkerPopupView: View {
    let marker: Marker
    /// When true this pop-up is doubling as the post-save confirmation: it shows
    /// a "Note Saved" badge instead of a separate banner (§9.7). The pop-up is
    /// the note the user just created/edited.
    var saved: Bool = false

    /// §9.6: image vs link decided by the `<img>` tag. A body image wins (shown
    /// as a thumbnail); otherwise a webpage link is surfaced as TEXT. NEVER a QR
    /// here — the QR lives on the detail card (§9.8).
    private var thumb: String? { marker.images.first }
    private var linkText: String? { thumb == nil ? marker.link : nil }

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                if saved {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 18, weight: .bold))
                        Text("Note Saved").font(.system(size: 18, weight: .bold))
                    }
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .background(MarkerColor.note).cornerRadius(8)
                }
                HStack(spacing: 10) {
                    Circle().fill(MarkerColor.dot(marker.kind)).frame(width: 12, height: 12)
                    Text(Html.timecode(marker.startsAt))
                        .font(.system(size: 20, weight: .semibold, design: .monospaced))
                        .foregroundStyle(MarkerColor.dot(marker.kind))
                    if marker.isNote {
                        Text("PRIVATE").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.bg).padding(.horizontal, 8).padding(.vertical, 2)
                            .background(MarkerColor.note).cornerRadius(4)
                    }
                }
                Text(marker.title.isEmpty ? (marker.isNote ? "Note" : "Annotation") : marker.title)
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.text).lineLimit(2)
                if !marker.bodyText.isEmpty {
                    Text(marker.bodyText).font(.system(size: 20)).foregroundStyle(Theme.textDim).lineLimit(3)
                }
                if let linkText {
                    Text(linkText)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(MarkerColor.dot(marker.kind))
                        .lineLimit(1).truncationMode(.middle)
                }
            }
            .frame(maxWidth: 460, alignment: .leading)
            if let thumb, let url = ImageURL.sized(thumb, width: 240) {
                RemoteImage(url: url).frame(width: 150, height: 96).clipped().cornerRadius(8)
            }
        }
        .padding(22)
        .background(.ultraThinMaterial)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(MarkerColor.dot(marker.kind).opacity(0.7), lineWidth: 2))
        .cornerRadius(16)
        .frame(maxWidth: 760, alignment: .leading)
    }
}

// MARK: - Detail card (§9.8)

struct DetailCardView: View {
    let marker: Marker
    let focusKey: String
    let truncated: Bool

    private var link: String? { marker.link }

    var body: some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                // §9.8: a single "Press BACK to close" hint replaces a focusable
                // close button — BACK already dismisses the card.
                Text("Press BACK to close")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .center)

                HStack {
                    // §9.8: play-icon "Go to {timecode}" button — default focus;
                    // OK seeks the playhead here and closes the card.
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill").font(.system(size: 20, weight: .bold))
                        Text("Go to \(Html.timecode(marker.startsAt))")
                            .font(.system(size: 24, weight: .semibold))
                    }
                    .foregroundStyle(focusKey == "goto" ? Theme.bg : MarkerColor.dot(marker.kind))
                    .padding(.horizontal, 18).padding(.vertical, 10)
                    .background(focusKey == "goto" ? Theme.gold : Color.white.opacity(0.12))
                    .cornerRadius(10)
                    if marker.isNote {
                        Text("PRIVATE").font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Theme.bg).padding(.horizontal, 8).padding(.vertical, 2)
                            .background(MarkerColor.note).cornerRadius(4)
                    }
                    Spacer()
                    if marker.isNote {
                        pillIcon("pencil", focused: focusKey == "edit")
                        pillIcon("trash", focused: focusKey == "delete")
                    }
                }
                Text(marker.title.isEmpty ? (marker.isNote ? "Note" : "Annotation") : marker.title)
                    .font(.system(size: 38, weight: .bold)).foregroundStyle(Theme.text)
                Rectangle().fill(Color.white.opacity(0.12)).frame(height: 1)

                imageArea

                if !marker.bodyText.isEmpty {
                    Text(marker.bodyText)
                        .font(.system(size: 24)).foregroundStyle(Theme.text)
                        .lineLimit(truncated ? 6 : nil)
                }

                if truncated {
                    Text("Press OK to read")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(focusKey == "readmore" ? Theme.bg : Theme.text)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .background(focusKey == "readmore" ? Theme.gold : Color.white.opacity(0.12))
                        .cornerRadius(8)
                }

                // §9.8: a webpage link → QR + the URL printed beneath it. Image
                // URLs are never QR'd (they render as images above).
                if let link {
                    HStack(alignment: .center, spacing: 18) {
                        ScanQR(string: link, size: 192)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Scan to open")
                                .font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.text)
                            // Only print the URL here when the body text doesn't
                            // already show it — otherwise it appears twice (§9.8).
                            if !marker.bodyText.contains(link) {
                                Text(link)
                                    .font(.system(size: 18)).foregroundStyle(Theme.textDim)
                                    .lineLimit(2).truncationMode(.middle)
                                    .frame(maxWidth: 520, alignment: .leading)
                            }
                        }
                    }
                }
            }
            .padding(40)
            .frame(maxWidth: 1100, alignment: .leading)
            .background(Theme.surface)
            .cornerRadius(20)
        }
    }

    /// §9.8 image area, presentation decided by COUNT: exactly one image renders
    /// LARGE + CENTERED; two or more render as a horizontal thumbnail strip.
    /// Both are focusable/selectable (OK → full-screen viewer, §9.9) with a
    /// single "Press OK to enlarge" hint above.
    @ViewBuilder
    private var imageArea: some View {
        if !marker.images.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Press OK to enlarge")
                    .font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.textDim)

                if marker.images.count == 1 {
                    if let url = ImageURL.sized(marker.images[0], width: 900) {
                        RemoteImage(url: url, contentMode: .fit)
                            .frame(maxWidth: 760, maxHeight: 300)
                            .overlay(RoundedRectangle(cornerRadius: 10)
                                .stroke(focusKey == "thumb0" ? Theme.gold : .clear, lineWidth: 4))
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                } else {
                    HStack(spacing: 16) {
                        ForEach(Array(marker.images.enumerated()), id: \.offset) { i, src in
                            if let url = ImageURL.sized(src, width: 360) {
                                RemoteImage(url: url)
                                    .frame(width: 220, height: 132).clipped().cornerRadius(8)
                                    .overlay(RoundedRectangle(cornerRadius: 8)
                                        .stroke(focusKey == "thumb\(i)" ? Theme.gold : .clear, lineWidth: 4))
                            }
                        }
                    }
                }
            }
        }
    }

    private func pillIcon(_ system: String, focused: Bool) -> some View {
        Image(systemName: system)
            .font(.system(size: 24)).foregroundStyle(focused ? Theme.bg : Theme.text)
            .frame(width: 52, height: 52)
            .background(focused ? Theme.gold : Color.white.opacity(0.12)).clipShape(Circle())
    }

}

// MARK: - Image viewer (§9.9)

struct ImageViewerView: View {
    let images: [String]
    let index: Int

    private var i: Int { images.isEmpty ? 0 : ((index % images.count) + images.count) % images.count }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let url = ImageURL.sized(images[safe: i], width: 1600) {
                RemoteImage(url: url, contentMode: .fit).ignoresSafeArea()
            }
            VStack {
                Spacer()
                if images.count > 1 {
                    Text("\(i + 1) / \(images.count)")
                        .font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.text)
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.black.opacity(0.6)).cornerRadius(8)
                }
                Text("BACK or OK to close").font(.system(size: 20)).foregroundStyle(Theme.textDim).padding(.top, 12)
            }.padding(.bottom, 60)
        }
    }
}

// MARK: - Text reader (§9.8)

struct TextReaderView: View {
    let title: String
    let text: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                if !title.isEmpty {
                    Text(title).font(.system(size: 38, weight: .bold)).foregroundStyle(Theme.text)
                }
                ScrollView {
                    Text(text).font(.system(size: 26)).foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .focusable()
                Text("BACK to close").font(.system(size: 20)).foregroundStyle(Theme.textDim)
            }
            .padding(60)
            .frame(maxWidth: 1300, maxHeight: 900)
            .background(Theme.surface).cornerRadius(20)
        }
    }
}

// MARK: - Settings pop-up (§9.11)

struct SettingsMenuView: View {
    let annotationPopups: Bool
    let notePopups: Bool
    let focusIndex: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings").font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.text)
                .padding(.bottom, 6)
            row("Annotation pop-ups", on: annotationPopups, focused: focusIndex == 0)
            row("Note pop-ups", on: notePopups, focused: focusIndex == 1)
        }
        .padding(28)
        .frame(width: 520, alignment: .leading)
        .background(Theme.surface).cornerRadius(16)
    }

    private func row(_ label: String, on: Bool, focused: Bool) -> some View {
        HStack {
            Text(label).font(.system(size: 24)).foregroundStyle(Theme.text)
            Spacer()
            Text(on ? "On" : "Off")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(on ? Theme.bg : Theme.text)
                .padding(.horizontal, 16).padding(.vertical, 6)
                .background(on ? Theme.gold : Color.white.opacity(0.14)).cornerRadius(20)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(focused ? Theme.text.opacity(0.14) : .clear).cornerRadius(10)
    }
}

// MARK: - Chapters pop-up (§9.2)

struct ChaptersMenuView: View {
    let chapters: [Chapter]
    let focusIndex: Int

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 4) {
                Text("Chapters")
                    .font(.system(size: 26, weight: .bold)).foregroundStyle(Theme.text)
                    .padding(.horizontal, 20).padding(.bottom, 10)
                ScrollViewReader { proxy in
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(chapters.enumerated()), id: \.offset) { i, ch in
                                row(ch, focused: i == focusIndex).id(i)
                            }
                        }
                    }
                    .onChange(of: focusIndex) { _, idx in
                        withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(idx, anchor: .center) }
                    }
                    .onAppear { proxy.scrollTo(focusIndex, anchor: .center) }
                }
            }
            .padding(.vertical, 28)
            .frame(width: 620, height: 720, alignment: .topLeading)
            .background(Theme.surface).cornerRadius(20)
            .padding(.trailing, 80).padding(.top, 150)
        }
    }

    private func row(_ ch: Chapter, focused: Bool) -> some View {
        HStack(spacing: 16) {
            Text(Html.timecode(ch.startsAt))
                .font(.system(size: 22, weight: .semibold, design: .monospaced))
                .foregroundStyle(focused ? Theme.bg : Theme.gold)
            Text(ch.title ?? "Chapter")
                .font(.system(size: 24))
                .foregroundStyle(focused ? Theme.bg : Theme.text)
                .lineLimit(1)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(focused ? Theme.gold : Color.clear)
        .cornerRadius(10)
        .padding(.horizontal, 16)
    }
}

// MARK: - Up Next card (mode A, §9.12)

struct UpNextCardView: View {
    let title: String
    let secondsLeft: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Up Next · \(secondsLeft)s")
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.gold)
            Text(title).font(.system(size: 28, weight: .bold)).foregroundStyle(Theme.text).lineLimit(2)
            HStack(spacing: 10) {
                Image(systemName: "play.fill")
                Text("Play now").font(.system(size: 22, weight: .semibold))
            }
            .foregroundStyle(Theme.bg)
            .padding(.horizontal, 22).padding(.vertical, 12)
            .background(Theme.gold).cornerRadius(10)
        }
        .padding(24)
        .frame(maxWidth: 520, alignment: .leading)
        .background(.ultraThinMaterial).cornerRadius(16)
    }
}

// MARK: - End recommendations panel (mode B, §9.12)

struct UpNextPanelView: View {
    let items: [RecItem]
    let focusIndex: Int

    var body: some View {
        ZStack {
            Color.black.opacity(0.85).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 28) {
                Text("More to explore").font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.text)
                HStack(spacing: 28) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { i, it in
                        VStack(alignment: .leading, spacing: 12) {
                            ZStack {
                                Theme.surface
                                if let url = ImageURL.sized(it.poster, width: 450) {
                                    RemoteImage(url: url)
                                }
                            }
                            .frame(width: 300, height: 169).clipped().cornerRadius(12)
                            .overlay(RoundedRectangle(cornerRadius: 12)
                                .stroke(focusIndex == i ? Theme.gold : .clear, lineWidth: 4))
                            .scaleEffect(focusIndex == i ? 1.06 : 1)
                            Text(it.title).font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Theme.text).lineLimit(2).frame(width: 300, alignment: .leading)
                        }
                    }
                }
            }
            .padding(60)
        }
    }
}

// MARK: - Save banner (§9.16)

struct SaveBannerView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 22, weight: .semibold)).foregroundStyle(Theme.bg)
            .padding(.horizontal, 24).padding(.vertical, 14)
            .background(Theme.gold).cornerRadius(12)
    }
}

// MARK: - Hold-to-seek indicator (§9.5)

struct SeekIndicatorView: View {
    let tier: Int
    let dir: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: dir < 0 ? "chevron.left" : "chevron.right")
            Text("\(tier)×").font(.system(size: 40, weight: .bold))
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 24).padding(.vertical, 14)
        .background(Color.black.opacity(0.6)).cornerRadius(12)
    }
}
