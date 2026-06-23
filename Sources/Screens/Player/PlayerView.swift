import SwiftUI

/// Fully custom TV player chrome over the native HLS `AVPlayer` (§9). The
/// `PlayerController` owns all state + the ported key handler; this view is the
/// presentation layer. A single `RemoteControlReceiver` holds focus and routes
/// every press to the controller (the SwiftUI focus engine is intentionally
/// not used for the chrome — see §9 platform notes).
struct PlayerView: View {
    @EnvironmentObject private var router: AppRouter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var c: PlayerController

    init(videoId: Int, startSeconds: Int? = nil) {
        _c = StateObject(wrappedValue: PlayerController(videoId: videoId, startSeconds: startSeconds))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let error = c.error {
                errorPanel(error)
            } else {
                // Hide the video surface until loading is done to prevent a
                // flash at 0:00 while the seek-to-resume position is in flight.
                PlayerSurface(player: c.engine.player)
                    .ignoresSafeArea()
                    .opacity(c.engine.isLoading ? 0 : 1)

                // Single focusable surface — captures all remote presses.
                RemoteControlReceiver(
                    onKeyDown: { c.handle($0) },
                    onKeyUp: { c.handleKeyUp($0) }
                )
                .ignoresSafeArea()

                if c.engine.isLoading { loadingOverlay }
                if let flash = c.flash { flashGlyph(flash) }

                // Ambient popup — TOP-CENTER. Centering clears the chrome's
                // top-LEFT title block and top-RIGHT icon row, so they don't
                // stack when chrome is up (e.g. right after saving a note, the
                // new marker's popup fires while controls are still visible).
                if let m = c.popupMarker {
                    MarkerPopupView(marker: m, saved: c.popupSaved)
                        .padding(.top, 60)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .transition(.opacity)
                }

                if let s = c.seekIndicator {
                    SeekIndicatorView(tier: s.tier, dir: s.dir)
                }

                // Mode-A up-next card (bottom-right).
                if c.upNextVisible, c.overlay == .none, let next = c.payload?.nextVideo {
                    UpNextCardView(title: next.title ?? "Next video", secondsLeft: c.upNextLeft)
                        .padding(.trailing, 80).padding(.bottom, 80)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }

                chrome.opacity(c.controlsVisible ? 1 : 0)

                // Pause wordmark sits ABOVE the chrome dim so it isn't washed
                // out by the scrim.
                if c.pauseChromeVisible { pauseChrome }

                // Peek control (§9.18) — persistent, FOCUSABLE top-RIGHT banner,
                // sitting just under the icon row (Add note / Settings). Drawn
                // ABOVE the chrome so the chrome's dim/scrim can't hide it: it
                // stays visible whenever peeking — playing, paused, chrome up or
                // down — so its position never changes. Top-right (not top-left)
                // because the paused/chrome title block occupies the top-left.
                // Focused via the `.peek` zone; SELECT resumes. The gold
                // highlight only shows while the chrome is up (zones are only
                // navigable then).
                if c.peeking, c.peekResumeSeconds != nil, c.overlay == .none {
                    PeekIndicatorView(
                        timecode: c.peekResumeLabel,
                        focused: c.controlsVisible && c.focusZone == .peek
                    )
                    .padding(.trailing, 80).padding(.top, 160)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(.opacity)
                }

                overlayLayer

                if let banner = c.saveBanner {
                    SaveBannerView(text: banner)
                        .padding(.trailing, 80).padding(.bottom, 80)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: c.controlsVisible)
        .animation(.easeOut(duration: 0.2), value: c.popupMarker)
        .animation(.easeOut(duration: 0.2), value: c.peeking)
        // BACK is handled here, not in the UIKit receiver: only `.onExitCommand`
        // reliably suppresses the NavigationStack's default pop on tvOS. If the
        // controller says the press was absorbed (overlay closed, chrome hidden),
        // we stay; otherwise we pop.
        .onExitCommand { if c.menuPressed() { dismiss() } }
        .onAppear {
            c.onExit = { dismiss() }
            c.onOpenEvent = { router.push(.eventDetail(id: $0, title: nil)) }
            c.start()
        }
        .onDisappear { c.teardown() }
    }

    // MARK: - Pause overlay (§9.10)

    private var pauseChrome: some View {
        // No scrim here — the dim now lives on the chrome (so it shows when
        // playing too and fades with the controls). This just adds the wordmark.
        ZStack {
            VStack {
                Spacer()
                HStack {
                    if c.hasWordmark, let url = ImageURL.sized(c.payload?.wordmarkUrl, width: ImageURL.wordmarkWidth) {
                        RemoteImage(url: url, contentMode: .fit, placeholder: .clear)
                            .frame(maxWidth: 720, maxHeight: 220, alignment: .leading)
                    } else if let title = c.payload?.eventTitle {
                        Text(title)
                            .font(.system(size: 64, weight: .bold)).foregroundStyle(Theme.text)
                    }
                    Spacer()
                }
                Spacer()
            }
            .padding(.leading, 90)
        }
    }

    // Shown over a black surface until the stream is ready AND the resume seek
    // has landed (§9.2) — so the video never flashes at 0:00 and then jumps to
    // the saved position.
    private var loadingOverlay: some View {
        VStack(spacing: 24) {
            ProgressView().scaleEffect(2).tint(Theme.text)
            Text("Loading…").font(.system(size: 26, weight: .medium)).foregroundStyle(Theme.textDim)
        }
    }

    private func flashGlyph(_ kind: String) -> some View {
        Image(systemName: kind == "pause" ? "pause.fill" : "play.fill")
            .font(.system(size: 70))
            .foregroundStyle(Theme.text)
            .padding(40)
            .background(Color.black.opacity(0.5)).clipShape(Circle())
    }

    // MARK: - Chrome (§9.3)

    private var chrome: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    if let et = c.payload?.eventTitle {
                        Text(et).font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.textDim)
                    }
                    if let t = c.payload?.title {
                        Text(t).font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.text)
                    }
                }
                Spacer()
                iconRow
            }
            .padding(.horizontal, 80).padding(.top, 60)

            Spacer()

            VStack(spacing: 18) {
                MarkerStripView(
                    markers: c.markers,
                    focused: c.focusZone == .markers,
                    focusIndex: c.markerIndex,
                    playheadIndex: c.playheadMarkerIndex,
                    centerNonce: c.markersCenterNonce
                )
                scrubBar
                HStack {
                    Text(Html.timecode(c.engine.currentTime))
                    Spacer()
                    Text("-\(Html.timecode(max(0, c.total - c.engine.currentTime)))")
                }
                .font(.system(size: 22, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .padding(.horizontal, 4)
                pillsRow
            }
            .padding(.horizontal, 80).padding(.bottom, 64)
        }
        .background(
            // A slight full-screen dim PLUS stronger top/bottom scrims so the
            // titles / icons / scrub / pills stay legible over bright frames.
            // All of it is part of the chrome view, so it fades in/out with the
            // controls (playing or paused) — same feel as the pause overlay.
            ZStack {
                Color.black.opacity(0.38)
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.45), location: 0),
                        .init(color: .clear, location: 0.3),
                        .init(color: .clear, location: 0.6),
                        .init(color: .black.opacity(0.6), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            }.ignoresSafeArea()
        )
    }

    private var iconRow: some View {
        HStack(spacing: 28) {
            ForEach(Array(c.iconKinds.enumerated()), id: \.offset) { i, kind in
                let focused = c.focusZone == .icons && c.iconIndex == i
                VStack(spacing: 8) {
                    Image(systemName: iconSystem(kind))
                        .font(.system(size: 30))
                        .foregroundStyle(focused ? Theme.bg : Theme.text)
                        .frame(width: 64, height: 64)
                        .background(iconActive(kind) ? Theme.gold.opacity(0.35) : Color.clear)
                        .background(focused ? Theme.gold : Color.white.opacity(0.14))
                        .clipShape(Circle())
                    Text(iconLabel(kind))
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.textDim)
                        .opacity(focused ? 1 : 0)
                }
            }
        }
    }

    private var scrubBar: some View {
        GeometryReader { geo in
            let focused = c.focusZone == .scrub
            let h: CGFloat = focused ? 12 : 6
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25)).frame(height: h)
                Capsule().fill(Theme.gold)
                    .frame(width: max(0, geo.size.width * c.playedFraction), height: h)
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .overlay { if let f = c.chapterFlash { chapterFlashOverlay(f, width: geo.size.width) } }
            .animation(.easeInOut(duration: 0.2), value: c.chapterFlash)
        }
        .frame(height: 24)
        .animation(.easeOut(duration: 0.15), value: c.focusZone)
    }

    /// Brief chapter cue: a tick at the chapter's point on the scrub + a name/
    /// timecode bubble above it, fading after ~2 s (§9.2). Replaces persistent
    /// scrub chapter markers (intentionally dropped).
    private func chapterFlashOverlay(_ flash: ChapterFlash, width: CGFloat) -> some View {
        let tickX = flash.fraction * width
        let bubbleX = min(max(120, tickX), width - 120)
        return ZStack {
            Rectangle().fill(Theme.gold).frame(width: 3, height: 22).position(x: tickX, y: 12)
            HStack(spacing: 8) {
                Text(flash.timecode)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Theme.gold)
                Text(flash.title).font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.text).lineLimit(1)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Color.black.opacity(0.85)).cornerRadius(8)
            .fixedSize()
            .position(x: bubbleX, y: -26)
        }
        .transition(.opacity)
    }

    private var pillsRow: some View {
        HStack(spacing: 18) {
            ForEach(Array(c.pillKinds.enumerated()), id: \.offset) { i, kind in
                let focused = c.focusZone == .pills && c.pillIndex == i
                HStack(spacing: 10) {
                    Image(systemName: pillSystem(kind))
                    Text(pillLabel(kind)).font(.system(size: 22, weight: .semibold))
                }
                .foregroundStyle(focused ? Theme.bg : Theme.text)
                .padding(.horizontal, 24).padding(.vertical, 14)
                .background(focused ? Theme.gold : Color.white.opacity(0.14))
                .cornerRadius(12)
            }
        }
    }

    // MARK: - Overlay layer (§9.15)

    @ViewBuilder
    private var overlayLayer: some View {
        switch c.overlay {
        case .settings:
            SettingsMenuView(annotationPopups: c.annotationPopups, notePopups: c.notePopups, speed: c.sessionSpeed, focusIndex: c.settingsIndex)
                .padding(.trailing, 80).padding(.top, 140)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        case .detail:
            if let m = c.activeMarker {
                DetailCardView(marker: m, focusKey: c.detailFocusKey, truncated: c.detailTruncated)
            }
        case .image:
            if let m = c.activeMarker { ImageViewerView(images: m.images, index: c.viewerIndex) }
        case .text:
            if let m = c.activeMarker { TextReaderView(title: m.title, text: m.bodyText) }
        case .upnextPanel:
            UpNextPanelView(items: c.recItems, focusIndex: c.recIndex)
        case .chapters:
            ChaptersMenuView(chapters: c.chapters, focusIndex: c.chapterIndex)
        case .qr:
            QrNoteOverlayView(
                videoId: c.payload?.videoId ?? 0,
                seconds: Int(c.engine.currentTime),
                editNoteId: c.qrEditNoteId,
                remintNonce: c.qrRemintNonce,
                focusIndex: c.qrFocus,
                onExpiredChange: { c.qrExpired = $0 },
                onSaved: { c.onNoteSaved() }
            )
        case .none:
            EmptyView()
        }
    }

    // MARK: - Error

    private func errorPanel(_ message: String) -> some View {
        VStack(spacing: 24) {
            Text(message).font(.system(size: 30)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            Button("Go back") { dismiss() }
        }
        .padding(60)
    }

    // MARK: - Icon/label maps

    private func iconSystem(_ k: String) -> String {
        switch k {
        case "addnote": return "square.and.pencil"
        case "chapters": return "list.bullet"
        case "cc": return "captions.bubble"
        default: return "gearshape"
        }
    }
    private func iconLabel(_ k: String) -> String {
        switch k {
        case "addnote": return "Add note"
        case "chapters": return "Chapters"
        case "cc": return "Subtitles"
        default: return "Settings"
        }
    }
    private func iconActive(_ k: String) -> Bool { k == "cc" && c.engine.captionsOn }

    private func pillSystem(_ k: String) -> String {
        switch k {
        case "restart": return "gobackward"
        case "playpause": return c.engine.isPlaying ? "pause.fill" : "play.fill"
        case "next": return "forward.end.fill"
        case "resume", "undo": return "arrow.uturn.backward"
        default: return "captions.bubble"
        }
    }
    private func pillLabel(_ k: String) -> String {
        switch k {
        case "restart": return "Restart"
        case "playpause": return c.engine.isPlaying ? "Pause" : "Play"
        case "next": return "Next video"
        case "resume": return "Resume \(c.peekResumeLabel)"
        case "undo": return "Undo"
        default: return c.engine.captionsOn ? "Subtitles on" : "Subtitles"
        }
    }
}

/// Non-destructive note peek control (§9.18). A persistent top-RIGHT pill (under
/// the icon row) shown the whole time a peek is active — playing, paused, chrome
/// up or down — so the cue never moves. Top-right because the paused/chrome title
/// block owns the top-left. It is **focusable + selectable** (the `.peek` focus
/// zone): when focused it highlights gold, and SELECT jumps back to the
/// preserved position.
struct PeekIndicatorView: View {
    let timecode: String
    var focused: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.backward").font(.system(size: 20))
            Text("Resume at \(timecode)").font(.system(size: 22, weight: .semibold))
        }
        .foregroundStyle(focused ? Theme.bg : Theme.text)
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Capsule().fill(focused ? Theme.gold : Color.black.opacity(0.6)))
        .overlay(Capsule().stroke(focused ? Theme.gold : Theme.gold.opacity(0.7), lineWidth: focused ? 2 : 1))
    }
}
