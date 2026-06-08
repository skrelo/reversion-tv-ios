import SwiftUI
import AVKit
import Combine

/// Owns the `AVPlayer` and publishes the playback state the custom chrome
/// renders (§9). tvOS plays HLS natively, so there's no third-party player —
/// we drive a bare `AVPlayer` and overlay our own D-pad UI (the stock
/// `AVPlayerViewController` chrome is intentionally NOT used, §9).
@MainActor
final class PlayerEngine: ObservableObject {
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying: Bool = false
    @Published var isLoading: Bool = true
    /// Bumped when the current item plays to its end (§9.13/§9.12).
    @Published var endedNonce: Int = 0
    @Published var hasCaptions: Bool = false
    @Published var captionsOn: Bool = false

    /// Per-tick side-effect hook (auto pop-ups + Up-Next windowing, §9.6/§9.12).
    var onTick: ((Double) -> Void)?
    /// Fired when the item plays to its end (§9.13).
    var onEnded: (() -> Void)?

    let player = AVPlayer()

    private var timeObserver: Any?
    private var statusObs: NSKeyValueObservation?
    private var rateObs: NSKeyValueObservation?
    private var likelyObs: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var pendingResume: Double = 0
    private var pendingSpeed: Float = 1
    private var didApplyResume = false
    private var legibleGroup: AVMediaSelectionGroup?

    init() {
        player.allowsExternalPlayback = false
        // 250 ms scrub UI tick (§9.1).
        let interval = CMTime(seconds: 0.25, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            let seconds = t.seconds.isFinite ? t.seconds : 0
            Task { @MainActor in
                guard let self else { return }
                self.currentTime = seconds
                if self.duration == 0,
                   let d = self.player.currentItem?.duration.seconds, d.isFinite, d > 0 {
                    self.duration = d
                }
                self.onTick?(self.currentTime)
            }
        }
        rateObs = player.observe(\.timeControlStatus, options: [.new]) { [weak self] p, _ in
            Task { @MainActor in
                guard let self else { return }
                self.isPlaying = p.timeControlStatus == .playing
                if p.timeControlStatus == .playing { self.isLoading = false }
            }
        }
    }

    deinit {
        if let timeObserver { player.removeTimeObserver(timeObserver) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
    }

    /// Load (or swap to) a stream and start playback, resuming to `resume`
    /// and applying the saved default speed (§9.2). Seeds `duration` from the
    /// payload so the scrub bar renders forwarded immediately (§9.4).
    func load(url: URL, resume: Double, durationHint: Double, speed: Float) {
        isLoading = true
        didApplyResume = false
        legibleGroup = nil
        hasCaptions = false
        pendingResume = resume
        pendingSpeed = speed
        currentTime = resume
        duration = durationHint > 0 ? durationHint : 0

        let item = AVPlayerItem(url: url)
        observe(item: item)
        player.replaceCurrentItem(with: item)
    }

    private func observe(item: AVPlayerItem) {
        statusObs?.invalidate()
        likelyObs?.invalidate()
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }

        statusObs = item.observe(\.status, options: [.new]) { [weak self] it, _ in
            Task { @MainActor in
                guard let self else { return }
                if it.status == .readyToPlay { self.onReady(item: it) }
            }
        }
        likelyObs = item.observe(\.isPlaybackLikelyToKeepUp, options: [.new]) { [weak self] it, _ in
            Task { @MainActor in
                guard let self else { return }
                if it.isPlaybackLikelyToKeepUp { self.isLoading = false }
            }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.endedNonce += 1
                self?.onEnded?()
            }
        }
    }

    private func onReady(item: AVPlayerItem) {
        let d = item.duration.seconds
        if d.isFinite, d > 0 { duration = d }

        if !didApplyResume {
            didApplyResume = true
            let watched = duration > 0 && pendingResume >= duration * 0.95
            if pendingResume > 1, !watched {
                player.seek(to: CMTime(seconds: pendingResume, preferredTimescale: 600),
                            toleranceBefore: .zero, toleranceAfter: .zero)
            }
            player.rate = pendingSpeed
            player.play()
        }
        isLoading = false
        configureCaptions(item: item)
    }

    // MARK: - Captions (media-selection based; embedded HLS tracks)

    /// Load the legible (subtitle) selection group asynchronously and cache it
    /// so the CC toggle is synchronous. CC is only offered when the manifest
    /// carries an embedded legible track (§9.17).
    private func configureCaptions(item: AVPlayerItem) {
        Task { @MainActor in
            let group = try? await item.asset.loadMediaSelectionGroup(for: .legible)
            self.legibleGroup = group
            self.hasCaptions = !(group?.options.isEmpty ?? true)
            self.applyCaptionSelection()
        }
    }

    private func applyCaptionSelection() {
        guard let item = player.currentItem, let group = legibleGroup else { return }
        if captionsOn, let first = group.options.first {
            item.select(first, in: group)
        } else {
            item.select(nil, in: group)
        }
    }

    func toggleCaptions() {
        captionsOn.toggle()
        applyCaptionSelection()
    }

    // MARK: - Transport

    func play() { player.play() }
    func pause() { player.pause() }

    func togglePlay() {
        if player.timeControlStatus == .playing { pause() } else { play() }
    }

    func restart() {
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        play()
    }

    /// Seek by a relative delta, clamped to [0, duration] (§9.4/§9.5).
    func seek(by delta: Double) {
        guard duration > 0 else { return }
        let target = min(duration, max(0, currentTime + delta))
        seek(to: target)
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        player.seek(to: CMTime(seconds: seconds, preferredTimescale: 600),
                    toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func setRate(_ rate: Float) {
        if player.timeControlStatus == .playing { player.rate = rate }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

/// Thin `UIViewRepresentable` that renders the engine's `AVPlayer` via an
/// `AVPlayerLayer` (full-bleed). No controls — the SwiftUI chrome sits on top.
struct PlayerSurface: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let v = PlayerLayerView()
        v.playerLayer.player = player
        v.playerLayer.videoGravity = .resizeAspect
        v.backgroundColor = .black
        return v
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

final class PlayerLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
