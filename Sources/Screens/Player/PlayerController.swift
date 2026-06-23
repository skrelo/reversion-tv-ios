import SwiftUI
import Combine

/// Chrome focus zones (§9.3). Top → bottom: icon row, markers strip, scrub
/// bar, transport pills.
/// `peek` is the focusable "Resume at {timecode}" banner, present only while a
/// note peek is active (§9.18); it sits between the icon row and the markers
/// strip in the vertical chain.
enum FocusZone { case icons, peek, markers, scrub, pills }

/// One modal layer at a time (§9.15). BACK unwinds inside-out.
enum PlayerOverlay { case none, settings, detail, image, text, qr, upnextPanel, chapters }

/// An end-of-video recommendation card (mode B, §9.12).
struct RecItem: Identifiable, Equatable {
    let id: Int
    let title: String
    let poster: String?
}

/// Transient chapter cue flashed over the scrub on select (§9.2). `fraction`
/// is the chapter's position along the timeline (0…1).
struct ChapterFlash: Equatable {
    let title: String
    let timecode: String
    let fraction: Double
}

/// Owns ALL player state + timers + the ported key handler (§9). Mirrors the
/// Tizen `Player` component / Android `PlaybackActivity`: the player owns focus
/// and key handling rather than the platform focus engine. Re-publishes the
/// `PlayerEngine`'s changes so the single SwiftUI view observes one object.
@MainActor
final class PlayerController: ObservableObject {
    // Timing constants (§9.1).
    private let seekStep: Double = 10
    private let saveIntervalMs: Double = 10_000
    private let autoHideMs: Double = 5_000
    private let upNextLead: Double = 15
    private let watched: Double = 0.95
    private let popupLifetimeMs: Double = 6_000
    private let popupWindow: Double = 1
    private let seekTiers: [Double] = [600, 1000, 1400, 1800]
    private let seekIndicatorFadeMs: Double = 600
    private let detailBodyClamp = 280
    // Note peek (§9.18) — mirror the mobile constants.
    private let peekAutocommitSec: Double = 300   // 5 min real playback → auto-commit
    private let peekUndoMs: Double = 5_000        // "Saved your spot · Undo" window
    private let peekEdgeStartSec = 5              // saved spot < 5 s from start → no Resume
    private let peekEdgeEndSec = 15.0            // saved spot within 15 s of end → no Resume

    let engine = PlayerEngine()

    // ── Data ──
    @Published var payload: StreamUrlResponse?
    @Published var markers: [Marker] = []
    @Published var chapters: [Chapter] = []
    @Published var error: String?
    @Published private(set) var videoId: Int

    /// When set (jump-to-note from My Notes, §11.4), overrides the saved
    /// resume point so playback starts at this exact timecode. One-shot:
    /// cleared after the first load so a later same-video reload still resumes.
    private var startSeconds: Int?

    // ── Chrome / focus ──
    @Published var controlsVisible = false
    @Published var focusZone: FocusZone = .scrub
    @Published var iconIndex = 0
    @Published var markerIndex = 0
    @Published var pillIndex = 1
    @Published var wordmarkFailed = false

    // ── Overlays ──
    @Published var overlay: PlayerOverlay = .none
    @Published var activeMarker: Marker?
    /// Current detail-card grid focus key. Empty = nothing highlighted (the
    /// card just opened); the first directional press enters the grid (§9.8).
    @Published var detailFocusKey = ""
    @Published var viewerIndex = 0
    @Published var settingsIndex = 0
    @Published var qrFocus = 0
    @Published var qrEditNoteId: Int?
    @Published var qrExpired = false
    @Published var qrRemintNonce = 0
    @Published var chapterIndex = 0

    // ── Ambient / transient ──
    @Published var popupMarker: Marker?
    /// True while `popupMarker` is doubling as the post-save confirmation (shows
    /// a "Note Saved" badge instead of a separate banner, §9.7).
    @Published var popupSaved = false
    @Published var saveBanner: String?
    @Published var flash: String?
    @Published var seekIndicator: (tier: Int, dir: Int)?
    @Published var markersCenterNonce = 0
    /// Brief cue shown above the scrub at a chapter's position on select (§9.2).
    @Published var chapterFlash: ChapterFlash?

    // ── Up-Next ──
    @Published var upNextVisible = false
    @Published var upNextLeft = 0
    @Published var recItems: [RecItem] = []
    @Published var recIndex = 0

    // ── Settings (in-player pop-up toggles + per-session speed, §9.11) ──
    @Published var annotationPopups = Prefs.annotationPopups
    @Published var notePopups = Prefs.notePopups
    @Published var sessionSpeed: Double = Prefs.playbackSpeed

    // ── Note peek (non-destructive jump, §9.18) ──
    /// True while a note jump is being previewed. Saved progress is FROZEN
    /// (`saveProgress` early-returns) so reviewing a note never clobbers the
    /// real watch position.
    @Published var peeking = false
    /// The preserved real position to return to (shown on the Resume control).
    @Published var peekResumeSeconds: Int?
    /// Non-nil for ~5 s after an auto-commit — drives the "Saved your spot ·
    /// Undo" affordance. Holds the position to restore if the user taps Undo.
    @Published var peekUndoRestore: Int?
    private var peekClock: Timer?
    private var peekPlayed = 0
    private var peekUndoWork: DispatchWorkItem?

    static let speedSteps: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    // ── Internal refs / timers ──
    private var bag = Set<AnyCancellable>()
    private var hideWork: DispatchWorkItem?
    private var popupWork: DispatchWorkItem?
    private var flashWork: DispatchWorkItem?
    private var bannerWork: DispatchWorkItem?
    private var indicatorWork: DispatchWorkItem?
    private var chapterFlashWork: DispatchWorkItem?
    private var saveTimer: Timer?
    private var seekTimer: Timer?
    private var seekHold: (dir: Int, start: Date)?
    private var firedPopupKeys = Set<String>()
    private var markerInit = false
    private var upNextDismissed = false
    private var wasPlaying = true
    private var lastSavedSecond = -1
    private var loadTask: Task<Void, Never>?

    /// Called when the player wants to leave (BACK on a bare/playing player).
    var onExit: (() -> Void)?
    /// Navigate to an event (mode-B recommendation OK).
    var onOpenEvent: ((Int) -> Void)?

    /// Captions exist for this video (backend authority, §9.2). Embedded HLS
    /// track availability is a separate concern handled by the engine (§9.17).
    var captionsAvailable: Bool { payload?.hasCaptions == true }
    var chaptersAvailable: Bool { !chapters.isEmpty }

    /// Bottom transport pills (§9.3): Restart, Play/Pause, Next. Subtitles is
    /// NOT here — it lives in the top-right icon row only (no duplication).
    private var pills: [String] {
        var p = ["restart", "playpause"]
        if payload?.nextVideo?.id != nil { p.append("next") }
        // Resume is NOT a pill — it's the focusable top-right banner (.peek zone,
        // §9.18). Undo is a transient pill shown for ~5 s after an auto-commit.
        if peekUndoRestore != nil { p.append("undo") }
        return p
    }

    /// Top-right icon row (§9.3): Add Note, Chapters, Subtitles, Settings.
    /// Chapters/Subtitles appear only when they exist.
    private var iconButtons: [String] {
        var b = ["addnote"]
        if chaptersAvailable { b.append("chapters") }
        if captionsAvailable { b.append("cc") }
        b.append("settings")
        return b
    }

    init(videoId: Int, startSeconds: Int? = nil) {
        self.videoId = videoId
        self.startSeconds = startSeconds
        // Re-publish engine changes so the view re-renders on time ticks etc.
        engine.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &bag)
        engine.onTick = { [weak self] t in self?.handleTick(t) }
        engine.onEnded = { [weak self] in self?.onEnded() }
        // Arm the auto-hide the moment playback truly starts (calling armHide
        // right after play() no-ops because timeControlStatus hasn't flipped to
        // .playing yet). Pausing cancels the hide so the controls stay up.
        engine.$isPlaying
            .removeDuplicates()
            .sink { [weak self] playing in
                guard let self else { return }
                if playing { self.armHide() } else { self.clearHide() }
            }
            .store(in: &bag)
    }

    // MARK: - Lifecycle

    func start() {
        loadStream()
        saveTimer = Timer.scheduledTimer(withTimeInterval: saveIntervalMs / 1000, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.engine.isPlaying else { return }
                self.saveProgress(self.engine.currentTime)
            }
        }
    }

    func teardown() {
        saveProgress(engine.currentTime)   // frozen while peeking — preserves the real spot
        loadTask?.cancel()
        saveTimer?.invalidate()
        seekTimer?.invalidate()
        peekClock?.invalidate()
        peekUndoWork?.cancel()
        engine.stop()
    }

    private func loadStream() {
        error = nil
        markerInit = false
        firedPopupKeys = []
        upNextDismissed = false
        wordmarkFailed = false
        markers = []
        chapters = []
        popupMarker = nil
        cancelPeekQuietly()
        peekUndoRestore = nil

        let vid = videoId
        loadTask?.cancel()
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let p = try await ApiClient.shared.streamUrl(videoId: vid)
                if Task.isCancelled { return }
                self.payload = p
                self.chapters = p.chapters ?? []
                self.markers = Markers.build(annotations: p.annotations ?? [], notes: [])
                guard let urlStr = p.hlsUrl, let url = URL(string: urlStr) else {
                    self.error = "This video is unavailable (no stream URL)."
                    return
                }
                // Jump-to-note (My Notes deep-link, §11.4) overrides the saved
                // resume point; it's a one-shot so a later reload of the same
                // video resumes normally.
                let noteSeek = self.startSeconds
                self.startSeconds = nil
                let savedProgress = p.progressSeconds ?? 0
                let resume = Double(noteSeek ?? savedProgress)
                self.seedFiredKeys(before: resume)
                self.engine.load(url: url,
                                 resume: resume,
                                 durationHint: Double(p.durationSeconds ?? 0),
                                 speed: Float(Prefs.playbackSpeed))
                self.loadNotes(annotations: p.annotations ?? [])
                // Non-destructive peek (§9.18): deep-linked onto a note over real
                // progress → freeze progress and offer Resume back. Duration is
                // unknown here, so the end-of-video guard is re-checked each tick.
                if let ns = noteSeek, self.shouldOfferResume(savedProgress, target: ns) {
                    self.enterPeek(resume: savedProgress, persist: false)
                }
            } catch {
                if Task.isCancelled { return }
                if (error as? ApiError)?.status == 401 { self.onExit?(); return }
                self.error = "Could not load this video."
            }
        }
    }

    private func loadNotes(annotations: [Annotation]) {
        let vid = videoId
        Task { [weak self] in
            guard let self else { return }
            let notes = (try? await ApiClient.shared.notes(videoId: vid))?.notes ?? []
            if Task.isCancelled || vid != self.videoId { return }
            self.markers = Markers.build(annotations: annotations, notes: notes)
            self.seedFiredKeys(before: self.engine.currentTime)
        }
    }

    /// Pre-mark markers before the resume point as fired so they don't pop in a
    /// barrage right after the resume seek (§9.2).
    private func seedFiredKeys(before time: Double) {
        for m in markers where m.startsAt < time - popupWindow {
            firedPopupKeys.insert(m.key)
        }
    }

    // MARK: - Progress (§9.13)

    private func saveProgress(_ seconds: Double) {
        // §9.18: while peeking a note, freeze progress so the preview never
        // overwrites the user's real saved position.
        guard !peeking else { return }
        let s = Int(seconds)
        guard s >= 1, s != lastSavedSecond else { return }
        lastSavedSecond = s
        let vid = videoId
        Task { try? await ApiClient.shared.saveProgress(videoId: vid, seconds: s) }
    }

    private func markComplete() {
        let dur = engine.duration
        guard dur > 0 else { return }
        let vid = videoId
        Task { try? await ApiClient.shared.saveProgress(videoId: vid, seconds: Int(dur)) }
    }

    // MARK: - Note peek (non-destructive jump & Resume, §9.18)

    /// Decide whether a "Resume at" peek is worth offering for a saved position.
    /// Skipped when never played, within a few seconds of the start/end, or
    /// effectively the same spot we're jumping to. The end check needs duration;
    /// at deep-link time it may still be 0, so it's re-validated each tick
    /// (`handleTick`) once the real duration is known.
    private func shouldOfferResume(_ resumeSec: Int, target: Int? = nil) -> Bool {
        guard resumeSec > 0 else { return false }
        if resumeSec < peekEdgeStartSec { return false }
        let dur = total
        if dur > 0, Double(resumeSec) >= dur - peekEdgeEndSec { return false }
        if let t = target, abs(resumeSec - t) <= 2 { return false }
        return true
    }

    /// Enter peek. `persist` force-saves the preserved position first (in-player
    /// "Go to", where the DB may be a few seconds stale); the deep-link path
    /// passes false because the DB already holds it (§9.18).
    private func enterPeek(resume: Int, persist: Bool) {
        if persist { lastSavedSecond = -1; saveProgress(Double(resume)) } // peeking still false
        peekUndoRestore = nil
        peekResumeSeconds = resume
        peeking = true
        startPeekClock()
    }

    /// Resume control → jump the playhead back to the preserved position.
    func resumeFromPeek() {
        guard let s = peekResumeSeconds else { return }
        stopPeekClock()
        peeking = false
        peekResumeSeconds = nil
        engine.seek(to: Double(s))
        clampPill()
        showControls(.pills)
    }

    /// End the peek; the current position becomes the new saved progress. Per
    /// §9.18 the ONLY trigger is the 5-min continuous-watch auto-commit —
    /// scrubbing and dismissing do NOT commit.
    private func commitPeek() {
        guard peeking else { return }
        stopPeekClock()
        peeking = false
        peekResumeSeconds = nil
        saveProgress(engine.currentTime)
        clampPill()
        redirectFocusOffPeek()
    }

    /// Drop the peek without touching playback (the saved spot turned out not to
    /// be worth returning to once duration was known).
    private func cancelPeekQuietly() {
        stopPeekClock()
        peeking = false
        peekResumeSeconds = nil
        clampPill()
        redirectFocusOffPeek()
    }

    /// If focus is sitting on the (now-gone) Resume banner, move it to a still-
    /// valid zone so the user isn't stranded on an invisible control.
    private func redirectFocusOffPeek() {
        guard focusZone == .peek else { return }
        focusZone = !markers.isEmpty ? .markers : .scrub
    }

    /// 5 min of real playback → commit + offer Undo for a few seconds.
    private func autoCommitPeek() {
        let restore = peekResumeSeconds
        commitPeek()
        peekUndoRestore = restore
        showBanner("Saved your spot")
        showControls()   // reveal chrome so the transient Undo pill is reachable
        peekUndoWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.peekUndoRestore = nil; self?.clampPill() }
        peekUndoWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + peekUndoMs / 1000, execute: work)
    }

    /// Undo an auto-commit → restore the old saved position and re-enter peek.
    func undoPeekCommit() {
        guard let restore = peekUndoRestore else { return }
        peekUndoWork?.cancel()
        peekUndoRestore = nil
        enterPeek(resume: restore, persist: true)   // writes the old spot back to the DB
        showControls(.pills)
    }

    private func startPeekClock() {
        stopPeekClock()
        peekPlayed = 0
        peekClock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                guard self.peeking else { self.stopPeekClock(); return }
                guard self.engine.isPlaying else { return }   // count real playback only
                self.peekPlayed += 1
                if Double(self.peekPlayed) >= self.peekAutocommitSec { self.autoCommitPeek() }
            }
        }
    }

    private func stopPeekClock() {
        peekClock?.invalidate(); peekClock = nil; peekPlayed = 0
    }

    /// Keep `pillIndex` valid when the pills array shrinks (Resume/Undo removed).
    private func clampPill() {
        let count = pills.count
        if pillIndex >= count { pillIndex = max(0, count - 1) }
    }

    var peekResumeLabel: String { peekResumeSeconds.map { Html.timecode(Double($0)) } ?? "" }

    // MARK: - Auto-hide

    private func clearHide() { hideWork?.cancel(); hideWork = nil }

    private func armHide() {
        clearHide()
        // Schedule unconditionally; decide whether to hide at FIRE time. The
        // play-state (engine.timeControlStatus) lags the play()/pause() call, so
        // checking it at schedule time both (a) fails to arm right after play
        // and (b) wrongly arms right after pause. At fire time it's settled:
        // hide only while actually playing with no modal — so a PAUSED player
        // keeps its controls up indefinitely (§9.10).
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.engine.isPlaying, self.overlay == .none, !self.upNextVisible else { return }
            self.controlsVisible = false
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + autoHideMs / 1000, execute: work)
    }

    private func showControls(_ zone: FocusZone? = nil) {
        controlsVisible = true
        if let zone { focusZone = zone }
        markersCenterNonce += 1
        armHide()
    }

    private func doFlash(_ kind: String) {
        flash = kind
        flashWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flash = nil }
        flashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    private func showBanner(_ text: String) {
        saveBanner = text
        bannerWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveBanner = nil }
        bannerWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2, execute: work)
    }

    // MARK: - Transport

    private func togglePlay() {
        if engine.isPlaying { engine.pause(); doFlash("pause") }
        else { engine.play(); doFlash("play") }
    }

    private func tierForHold(_ ms: Double) -> Int {
        var tier = 1
        for (i, t) in seekTiers.enumerated() where ms >= t { tier = i + 2 }
        return tier
    }

    private func showSeekIndicator(_ tier: Int, _ dir: Int) {
        seekIndicator = (tier, dir)
        indicatorWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.seekIndicator = nil }
        indicatorWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seekIndicatorFadeMs / 1000, execute: work)
    }

    /// First tap = clean 10 s jump; holding escalates 1×→5× on a 250 ms timer
    /// (§9.5). The repeating timer replaces the browser key-repeat the web port
    /// relies on (tvOS sends one press, not repeats).
    private func startSeek(_ dir: Int) {
        // §9.18: scrubbing while peeking is part of reviewing the note — it must
        // NOT commit. Saving stays frozen and the Resume control stays put; only
        // selecting Resume or the 5-min auto-commit ends the peek.
        seekTimer?.invalidate()
        seekHold = (dir, Date())
        seekTick(dir)
        seekTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.seekTick(dir) }
        }
    }

    private func seekTick(_ dir: Int) {
        let tier: Int = {
            guard let h = seekHold, h.dir == dir else { return 1 }
            return tierForHold(Date().timeIntervalSince(h.start) * 1000)
        }()
        engine.seek(by: Double(dir) * seekStep * Double(tier))
        if tier >= 2 { showSeekIndicator(tier, dir) }
        showControls(.scrub)
        // Forward seeks clear skipped markers' fired state; back seeks re-arm.
        rearmPopups(around: engine.currentTime, forward: dir > 0)
    }

    private func endSeek() {
        seekTimer?.invalidate(); seekTimer = nil
        seekHold = nil
    }

    private func rearmPopups(around t: Double, forward: Bool) {
        if forward {
            for m in markers where m.startsAt < t { firedPopupKeys.insert(m.key) }
        } else {
            for m in markers where m.startsAt >= t { firedPopupKeys.remove(m.key) }
        }
    }

    // MARK: - Markers / icons / pills

    private func enterMarkers() {
        if !markerInit {
            if let idx = Markers.nearestIndex(markers, time: engine.currentTime) { markerIndex = idx }
            markerInit = true
        }
        focusZone = .markers
    }

    private func activateIcon() {
        let kind = iconButtons[safe: iconIndex] ?? "settings"
        switch kind {
        case "addnote": qrEditNoteId = nil; qrFocus = 0; qrExpired = false; openModal(.qr)
        case "chapters": openChapters()
        case "cc": engine.toggleCaptions(); armHide()
        default: settingsIndex = 0; openModal(.settings)
        }
    }

    private func activatePill() {
        let kind = pills[safe: pillIndex] ?? "playpause"
        switch kind {
        case "restart":
            engine.restart()
            firedPopupKeys = []
            showControls(.pills)
        case "playpause": togglePlay(); armHide()
        case "undo": undoPeekCommit()
        case "next": advanceNext()
        case "cc": engine.toggleCaptions(); armHide()
        default: break
        }
    }

    // MARK: - Modal helpers (pause while up, §9.7/§9.8)

    private func openModal(_ name: PlayerOverlay) {
        wasPlaying = engine.isPlaying
        if engine.isPlaying { engine.pause() }
        clearHide()
        overlay = name
    }

    func closeModal() {
        overlay = .none
        if wasPlaying { engine.play() }
        armHide()
    }

    private func openDetail(_ marker: Marker) {
        activeMarker = marker
        // §9.8: open with NOTHING highlighted so "Go to {timecode}" isn't
        // pre-selected (avoids an accidental seek on a reflexive OK). The first
        // directional press enters the grid at the top-left button.
        detailFocusKey = ""
        openModal(.detail)
    }

    /// Open the Chapters pop-up, landing on the chapter nearest the playhead.
    private func openChapters() {
        if let idx = nearestChapterIndex(engine.currentTime) { chapterIndex = idx }
        openModal(.chapters)
    }

    /// Flash the chapter name + timecode above the scrub at its position for
    /// ~2 s (§9.2). The only chapter cue on the scrub — no persistent ticks.
    private func showChapterFlash(_ ch: Chapter) {
        let frac = total > 0 ? ch.startsAt / total : 0
        chapterFlash = ChapterFlash(
            title: ch.title ?? "Chapter",
            timecode: Html.timecode(ch.startsAt),
            fraction: min(1, max(0, frac))
        )
        chapterFlashWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.chapterFlash = nil }
        chapterFlashWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    private func nearestChapterIndex(_ time: Double) -> Int? {
        guard !chapters.isEmpty else { return nil }
        // Last chapter whose start is <= time (the one currently playing).
        var best = 0
        for (i, ch) in chapters.enumerated() where ch.startsAt <= time { best = i }
        return best
    }

    /// §9.8: detail-card focus is a **2D grid**, not a flat list. Row 0 is the
    /// top button row (Go to → Edit/Delete for notes → Close); row 1 is the
    /// image row (LEFT/RIGHT page images); row 2 is the "Press OK to read"
    /// button. LEFT/RIGHT stay within a row; UP/DOWN move between rows.
    func detailRows(_ marker: Marker?) -> [[String]] {
        guard let marker else { return [["goto"]] }
        var rows: [[String]] = []
        var top: [String] = ["goto"]
        if marker.isNote { top.append("edit"); top.append("delete") }
        rows.append(top)
        if !marker.images.isEmpty {
            rows.append(marker.images.indices.map { "thumb\($0)" })
        }
        if marker.bodyText.count > detailBodyClamp {
            rows.append(["readmore"])
        }
        return rows
    }

    /// (row, col) of `key` in the grid; defaults to the top-left button.
    private func detailPosition(_ rows: [[String]], key: String) -> (Int, Int) {
        for (r, row) in rows.enumerated() {
            if let c = row.firstIndex(of: key) { return (r, c) }
        }
        return (0, 0)
    }

    var detailTruncated: Bool {
        guard let m = activeMarker else { return false }
        return m.bodyText.count > detailBodyClamp
    }

    private func deleteNote(_ marker: Marker) {
        let vid = videoId
        let annotations = payload?.annotations ?? []
        Task { [weak self] in
            guard let self else { return }
            do {
                try await ApiClient.shared.deleteNote(videoId: vid, noteId: marker.entityId)
                self.loadNotes(annotations: annotations)
                self.showBanner("Note deleted")
            } catch {
                self.showBanner("Could not delete note")
            }
        }
    }

    /// After the phone saves a note, reload markers and surface the just-saved
    /// note as the ambient pop-up WITH a "Note Saved" badge — this replaces the
    /// separate save banner (one combined confirmation, §9.7). Forced to show
    /// regardless of the note-pop-up toggle, since it's a save acknowledgement.
    func onNoteSaved() {
        closeModal()
        let vid = videoId
        let at = engine.currentTime
        Task { [weak self] in
            guard let self else { return }
            let notes = (try? await ApiClient.shared.notes(videoId: vid))?.notes ?? []
            if Task.isCancelled || vid != self.videoId { return }
            self.markers = Markers.build(annotations: self.payload?.annotations ?? [], notes: notes)
            self.seedFiredKeys(before: self.engine.currentTime)
            guard let saved = self.nearestNoteMarker(to: at) else { return }
            self.firedPopupKeys.insert(saved.key)   // don't let the tick double-fire it
            self.showSavedPopup(saved)
        }
    }

    /// The note marker closest to `time` — the one the user just added/edited.
    private func nearestNoteMarker(to time: Double) -> Marker? {
        markers.filter { $0.isNote }
            .min { abs($0.startsAt - time) < abs($1.startsAt - time) }
    }

    private func showSavedPopup(_ m: Marker) {
        popupSaved = true
        popupMarker = m
        popupWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.popupMarker = nil; self?.popupSaved = false }
        popupWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + popupLifetimeMs / 1000, execute: work)
    }

    private func persistSetting(_ index: Int, direction: Int = 1) {
        switch index {
        case 0:
            annotationPopups.toggle(); Prefs.annotationPopups = annotationPopups
        case 1:
            notePopups.toggle(); Prefs.notePopups = notePopups
        case 2:
            let steps = Self.speedSteps
            let current = steps.firstIndex(where: { abs($0 - sessionSpeed) < 0.01 }) ?? 2
            let next = (current + direction + steps.count) % steps.count
            sessionSpeed = steps[next]
            Prefs.playbackSpeed = sessionSpeed
            engine.setRate(Float(sessionSpeed))
        default: break
        }
    }

    // MARK: - Up Next (§9.12)

    private func advanceNext() {
        guard let next = payload?.nextVideo?.id else { return }
        markComplete()
        upNextVisible = false
        overlay = .none
        controlsVisible = true
        focusZone = .pills
        pillIndex = 1
        videoId = next
        loadStream()
    }

    private func onEnded() {
        markComplete()
        if Prefs.autoplayNext, payload?.nextVideo?.id != nil { advanceNext() }
        else { openRecommendations() }
    }

    private func openRecommendations() {
        let evId = payload?.eventId
        Task { [weak self] in
            guard let self else { return }
            guard let home = try? await ApiClient.shared.home() else { self.onExit?(); return }
            var seen = Set<Int>()
            var items: [RecItem] = []
            let merged = (home.recentEvents ?? []) + (home.upcomingEvents ?? [])
            for e in merged {
                guard let id = e.id, id != evId, !seen.contains(id) else { continue }
                seen.insert(id)
                let poster = e.cardPosterUrl ?? e.posterUrl ?? e.coverUrl ?? e.backdropUrl
                items.append(RecItem(id: id, title: e.title ?? "", poster: poster))
                if items.count >= 4 { break }
            }
            if items.isEmpty { self.onExit?(); return }
            self.recItems = items
            self.recIndex = 0
            self.controlsVisible = false
            self.overlay = .upnextPanel
        }
    }

    // MARK: - Per-tick (pop-ups + Up-Next windowing)

    private func handleTick(_ t: Double) {
        // Re-validate the peek now that duration may be known: drop the Resume
        // if the preserved spot turns out to be within the end window (§9.18).
        if peeking, let r = peekResumeSeconds, !shouldOfferResume(r) { cancelPeekQuietly() }
        maybePopup(t)
        guard Prefs.autoplayNext, payload?.nextVideo?.id != nil,
              engine.duration > 0, !upNextDismissed, overlay == .none else {
            if upNextVisible && overlay != .none { upNextVisible = false }
            return
        }
        let remaining = engine.duration - t
        let left = Int(ceil(remaining))
        if remaining <= upNextLead, left > 0 {
            upNextLeft = left
            if !upNextVisible { upNextVisible = true }
        } else if upNextVisible {
            upNextVisible = false
        }
    }

    private func maybePopup(_ t: Double) {
        guard overlay == .none, !upNextVisible else { return }
        for m in markers where !firedPopupKeys.contains(m.key) {
            if abs(t - m.startsAt) <= popupWindow, t >= m.startsAt {
                firedPopupKeys.insert(m.key)
                let enabled = m.kind == .annotation ? annotationPopups : notePopups
                if !enabled { continue }
                popupSaved = false
                popupMarker = m
                popupWork?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.popupMarker = nil; self?.popupSaved = false }
                popupWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + popupLifetimeMs / 1000, execute: work)
                break
            }
        }
    }

    // MARK: - Key handling (ported from Tizen/Android, §9)

    /// Non-BACK key release (BACK is handled via `menuPressed()` / `.onExitCommand`).
    func handleKeyUp(_ key: RemoteKey) {
        if key == .left || key == .right { endSeek() }
    }

    /// BACK / Menu press, routed via SwiftUI `.onExitCommand` (the only reliable
    /// way to suppress the `NavigationStack` pop on tvOS — consuming the raw press
    /// in the UIKit receiver does not stop the system pop). Returns true if the
    /// player should exit, false if the press was absorbed (overlay closed, etc).
    func menuPressed() -> Bool {
        let exit = resolveMenu()
        #if DEBUG
        print("[Player] BACK overlay=\(overlay) upNext=\(upNextVisible) playing=\(engine.isPlaying) controls=\(controlsVisible) -> exit=\(exit)")
        #endif
        return exit
    }

    private func resolveMenu() -> Bool {
        // Inside-out: any modal overlay closes first (§9.15).
        switch overlay {
        case .qr, .detail, .settings, .chapters: closeModal(); return false
        case .image, .text: overlay = .detail; return false
        case .upnextPanel: return true // end recommendations → exit player
        case .none: break
        }
        // Mode-A up-next card → dismiss it, stay on video.
        if upNextVisible { upNextVisible = false; upNextDismissed = true; return false }
        // Netflix double-back (§9.10): paused chrome up → hide it, stay on video.
        if !engine.isPlaying, controlsVisible { controlsVisible = false; clearHide(); return false }
        return true
    }

    func handle(_ key: RemoteKey) -> Bool {
        switch overlay {
        case .qr: return handleQr(key)
        case .image: return handleImage(key)
        case .text: return handleText(key)
        case .detail: return handleDetail(key)
        case .settings: return handleSettings(key)
        case .upnextPanel: return handleUpNextPanel(key)
        case .chapters: return handleChapters(key)
        case .none: break
        }

        // Mode-A up-next card.
        if upNextVisible {
            switch key {
            case .select, .playPause: advanceNext(); return true
            case .menu, .down: upNextVisible = false; upNextDismissed = true; return true
            default: return true
            }
        }

        // BACK (Netflix double-back, §9.10).
        if key == .menu {
            if !engine.isPlaying, controlsVisible {
                controlsVisible = false; clearHide(); return true
            }
            return false // bubble → exit player
        }

        if key == .playPause { togglePlay(); showControls(); return true }

        // Bare player (no chrome).
        if !controlsVisible {
            switch key {
            case .select: togglePlay(); showControls(.pills)
            case .left: startSeek(-1)
            case .right: startSeek(1)
            case .up, .down: showControls(.pills)
            default: break
            }
            return true
        }

        // Chrome visible: zone navigation.
        armHide()
        let hasMarkers = !markers.isEmpty
        switch focusZone {
        case .icons:
            switch key {
            case .left: iconIndex = max(0, iconIndex - 1)
            case .right: iconIndex = min(iconButtons.count - 1, iconIndex + 1)
            case .down:
                if peeking { focusZone = .peek }
                else if hasMarkers { enterMarkers() } else { focusZone = .scrub }
            case .up: break // §9.3: ceiling is a HARD STOP — never hide the chrome.
            case .select: activateIcon()
            default: break
            }
        case .peek:
            // The focusable Resume banner (§9.18). UP → icons; DOWN → markers/
            // scrub; SELECT jumps back to the preserved position.
            switch key {
            case .up: focusZone = .icons
            case .down: if hasMarkers { enterMarkers() } else { focusZone = .scrub }
            case .select: resumeFromPeek()
            default: break
            }
        case .markers:
            switch key {
            case .left: markerIndex = max(0, markerIndex - 1)
            case .right: markerIndex = min(markers.count - 1, markerIndex + 1)
            case .up: focusZone = peeking ? .peek : .icons
            case .down: focusZone = .scrub
            case .select:
                // §9.6: do NOT auto-seek on open — the jump is an explicit press
                // on the card's "Go to {timecode}" button (§9.8).
                if let m = markers[safe: markerIndex] { openDetail(m) }
            default: break
            }
        case .scrub:
            switch key {
            case .left: startSeek(-1)
            case .right: startSeek(1)
            case .select: togglePlay()
            case .down: focusZone = .pills
            case .up:
                if hasMarkers { enterMarkers() }
                else if peeking { focusZone = .peek } else { focusZone = .icons }
            default: break
            }
        case .pills:
            switch key {
            case .left: pillIndex = max(0, pillIndex - 1)
            case .right: pillIndex = min(pills.count - 1, pillIndex + 1)
            case .select: activatePill()
            case .up: focusZone = .scrub
            case .down: break // §9.3: floor is a HARD STOP — never hide the chrome.
            default: break
            }
        }
        return true
    }

    // ── Overlay handlers ──

    private func handleQr(_ key: RemoteKey) -> Bool {
        switch key {
        case .left, .right: qrFocus = qrFocus == 0 ? 1 : 0
        case .select:
            if qrExpired && qrFocus == 0 { qrExpired = false; qrFocus = 0; qrRemintNonce += 1 }
            else { closeModal() }
        case .menu: closeModal()
        default: break
        }
        return true
    }

    private func handleImage(_ key: RemoteKey) -> Bool {
        switch key {
        case .left: viewerIndex -= 1
        case .right: viewerIndex += 1
        case .menu, .select: overlay = .detail
        default: break
        }
        return true
    }

    private func handleText(_ key: RemoteKey) -> Bool {
        switch key {
        case .menu, .select: overlay = .detail
        default: break // UP/DOWN scrolling handled by the SwiftUI ScrollView focus
        }
        return true
    }

    private func handleDetail(_ key: RemoteKey) -> Bool {
        let rows = detailRows(activeMarker)
        // Nothing highlighted yet (card just opened, §9.8): a directional press
        // enters the grid at the top-left button; OK is ignored so a reflexive
        // press can't accidentally seek; BACK closes.
        let allKeys = rows.flatMap { $0 }
        if !allKeys.contains(detailFocusKey) {
            switch key {
            case .up, .down, .left, .right: detailFocusKey = rows.first?.first ?? ""
            case .menu: closeModal()
            default: break
            }
            return true
        }
        let (r, c) = detailPosition(rows, key: detailFocusKey)
        switch key {
        // LEFT/RIGHT stay within the current row (never jump rows, §9.8).
        case .left: if c > 0 { detailFocusKey = rows[r][c - 1] }
        case .right: if c < rows[r].count - 1 { detailFocusKey = rows[r][c + 1] }
        // UP/DOWN move between rows, keeping the column where possible.
        case .up:
            if r > 0 { let nr = r - 1; detailFocusKey = rows[nr][min(c, rows[nr].count - 1)] }
        case .down:
            if r < rows.count - 1 { let nr = r + 1; detailFocusKey = rows[nr][min(c, rows[nr].count - 1)] }
        case .menu: closeModal()
        case .select:
            switch detailFocusKey {
            case "goto":
                // §9.8: jump the playhead to the marker, then close (closeModal
                // resumes playback if the video was playing before the card).
                // For a NOTE the jump is a non-destructive peek (§9.18); for an
                // annotation (coach content) it seeks directly.
                if let m = activeMarker {
                    if m.isNote {
                        let from = Int(engine.currentTime)
                        if shouldOfferResume(from, target: Int(m.startsAt)) {
                            enterPeek(resume: from, persist: true)
                        }
                    }
                    engine.seek(to: m.startsAt)
                }
                closeModal()
            case "readmore": overlay = .text
            case "edit":
                if let m = activeMarker { qrEditNoteId = m.entityId; qrFocus = 0; qrExpired = false; overlay = .qr }
            case "delete":
                if let m = activeMarker { deleteNote(m); closeModal() }
            default:
                if detailFocusKey.hasPrefix("thumb") {
                    viewerIndex = Int(detailFocusKey.dropFirst(5)) ?? 0
                    overlay = .image
                }
            }
        default: break
        }
        return true
    }

    private func handleSettings(_ key: RemoteKey) -> Bool {
        switch key {
        case .up: settingsIndex = max(0, settingsIndex - 1)
        case .down: settingsIndex = min(2, settingsIndex + 1)
        case .select, .right: persistSetting(settingsIndex, direction: 1)
        case .left: persistSetting(settingsIndex, direction: -1)
        case .menu: closeModal()
        default: break
        }
        return true
    }

    private func handleChapters(_ key: RemoteKey) -> Bool {
        switch key {
        case .up: chapterIndex = max(0, chapterIndex - 1)
        case .down: chapterIndex = min(chapters.count - 1, chapterIndex + 1)
        case .select:
            if let ch = chapters[safe: chapterIndex] {
                let forward = ch.startsAt >= engine.currentTime
                showChapterFlash(ch)
                engine.seek(to: ch.startsAt)
                rearmPopups(around: ch.startsAt, forward: forward)
                closeModal()
            }
        case .menu: closeModal()
        default: break
        }
        return true
    }

    private func handleUpNextPanel(_ key: RemoteKey) -> Bool {
        switch key {
        case .left: recIndex = max(0, recIndex - 1)
        case .right: recIndex = min(recItems.count - 1, recIndex + 1)
        case .select: if let it = recItems[safe: recIndex] { onOpenEvent?(it.id) }
        case .menu: onExit?()
        default: break
        }
        return true
    }

    // MARK: - Derived for the view

    var pillKinds: [String] { pills }
    var iconKinds: [String] { iconButtons }
    var total: Double { engine.duration > 0 ? engine.duration : Double(payload?.durationSeconds ?? 0) }
    var playedFraction: Double { total > 0 ? engine.currentTime / total : 0 }
    var hasWordmark: Bool { (payload?.wordmarkUrl?.isEmpty == false) && !wordmarkFailed }
    var pauseChromeVisible: Bool { controlsVisible && !engine.isPlaying && overlay == .none && !upNextVisible }
    var playheadMarkerIndex: Int? { Markers.nearestIndex(markers, time: engine.currentTime) }
}

extension Array {
    /// Safe subscript — returns nil instead of trapping out of range.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
