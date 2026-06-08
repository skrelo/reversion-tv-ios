import SwiftUI

/// Phone-compose QR companion (§9.7). The TV mints a one-time code, shows a QR
/// the phone scans (or the user types the code in the Reversion app), and polls
/// until the phone saves the note. The player pauses while this is up and OWNS
/// key handling (focus index + expired-state OK behavior); this view owns the
/// network lifecycle only. Mirrors the Tizen `QrNoteOverlay`.
@MainActor
final class QrNoteModel: ObservableObject {
    @Published var status = "Getting a code…"
    @Published var code = ""
    @Published var shortURL = ""
    @Published var scanURL = ""
    @Published var expired = false

    private var pollTask: Task<Void, Never>?
    private var cancelled = false
    private var terminal = false
    private var saved = false
    private var currentCode: String?

    var onExpiredChange: ((Bool) -> Void)?
    var onSaved: (() -> Void)?

    func mint(videoId: Int, seconds: Int, editNoteId: Int?) {
        guard !cancelled, !terminal else { return }
        pollTask?.cancel()
        status = "Getting a code…"
        code = ""; scanURL = ""
        Task { [weak self] in
            guard let self else { return }
            do {
                let res = try await ApiClient.shared.requestTvNoteCode(
                    videoId: videoId, seconds: seconds, noteId: editNoteId)
                if self.cancelled || self.terminal { return }
                self.currentCode = res.code
                self.code = res.code ?? ""
                self.shortURL = res.shortUrl ?? ""
                self.scanURL = res.scanUrl ?? (res.code ?? "")
                self.status = "Waiting for your phone…"
                let interval = max(2.0, Double(res.pollInterval ?? 3))
                self.poll(every: interval)
            } catch {
                if !self.cancelled { self.status = "Could not reach the server. Check your connection." }
            }
        }
    }

    private func markExpired() {
        guard !cancelled, !terminal else { return }
        terminal = true
        pollTask?.cancel()
        currentCode = nil // dead code — don't cancel on close
        expired = true
        onExpiredChange?(true)
    }

    private func poll(every interval: Double) {
        guard !cancelled, !terminal, let code = currentCode else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            do {
                let res = try await ApiClient.shared.pollTvNoteCode(code)
                if self.cancelled { return }
                switch res.status {
                case "scanned": self.status = "Scanned — composing on your phone…"
                case "completed":
                    self.terminal = true; self.saved = true; self.status = "Saved!"
                    self.onSaved?(); return
                case "cancelled": self.terminal = true; self.status = "Cancelled."; return
                case "expired": self.markExpired(); return
                default: break
                }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if !self.cancelled { self.poll(every: interval) }
            } catch {
                if self.cancelled { return }
                if let s = (error as? ApiError)?.status, s == 404 || s == 410 { self.markExpired(); return }
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if !self.cancelled { self.poll(every: interval) }
            }
        }
    }

    func reset() {
        cancelled = false; terminal = false; saved = false; expired = false
        onExpiredChange?(false)
    }

    func dispose() {
        cancelled = true
        pollTask?.cancel()
        if let code = currentCode, !saved {
            Task { try? await ApiClient.shared.cancelTvNoteCode(code) }
        }
    }
}

struct QrNoteOverlayView: View {
    let videoId: Int
    let seconds: Int
    let editNoteId: Int?
    let remintNonce: Int
    let focusIndex: Int
    let onExpiredChange: (Bool) -> Void
    let onSaved: () -> Void

    @StateObject private var model = QrNoteModel()

    var body: some View {
        ZStack {
            Color.black.opacity(0.8).ignoresSafeArea()
            VStack(spacing: 28) {
                if model.expired {
                    VStack(spacing: 12) {
                        Text("Note code expired").font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.text)
                        Text("This code timed out. Get a fresh code to add your note.")
                            .font(.system(size: 22)).foregroundStyle(Theme.textDim)
                    }
                } else {
                    HStack(alignment: .top, spacing: 40) {
                        Group {
                            if model.scanURL.isEmpty {
                                ProgressView().frame(width: 256, height: 256)
                            } else {
                                ScanQR(string: model.scanURL, size: 256)
                            }
                        }
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Add a note at \(Html.timecode(Double(seconds)))")
                                .font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)
                            Text(model.status).font(.system(size: 22)).foregroundStyle(Theme.gold)
                            Text("Scan with your phone camera, or in the Reversion app go to Account → “Add/edit a note from your TV” → Scan note QR from TV (or type the code there).")
                                .font(.system(size: 20)).foregroundStyle(Theme.textDim)
                                .frame(maxWidth: 560, alignment: .leading)
                            if !model.code.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Scan it, or enter this code in the app")
                                        .font(.system(size: 16)).foregroundStyle(Theme.textDim)
                                    Text(formatCode(model.code))
                                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                                        .foregroundStyle(Theme.text)
                                }
                            }
                            if !model.shortURL.isEmpty {
                                Text("No app? Go to \(model.shortURL)")
                                    .font(.system(size: 18)).foregroundStyle(Theme.textDim)
                            }
                        }
                    }
                }

                HStack(spacing: 20) {
                    qrButton(model.expired ? "Get a new code" : "Continue watching", focused: focusIndex == 0, primary: true)
                    qrButton(model.expired ? "Close" : "Cancel", focused: focusIndex == 1, primary: false)
                }
            }
            .padding(48)
            .background(Theme.surface).cornerRadius(24)
        }
        .onAppear {
            model.onExpiredChange = onExpiredChange
            model.onSaved = onSaved
            model.reset()
            model.mint(videoId: videoId, seconds: seconds, editNoteId: editNoteId)
        }
        .onChange(of: remintNonce) { _, _ in
            model.reset()
            model.mint(videoId: videoId, seconds: seconds, editNoteId: editNoteId)
        }
        .onDisappear { model.dispose() }
    }

    private func qrButton(_ label: String, focused: Bool, primary: Bool) -> some View {
        Text(label)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(focused ? Theme.bg : Theme.text)
            .padding(.horizontal, 28).padding(.vertical, 14)
            .background(focused ? Theme.gold : Color.white.opacity(primary ? 0.18 : 0.10))
            .cornerRadius(12)
    }

    /// Mid-dash the code for across-the-room legibility (matches pairing).
    private func formatCode(_ raw: String) -> String {
        guard raw.count > 4 else { return raw }
        let half = raw.count / 2
        let idx = raw.index(raw.startIndex, offsetBy: half)
        return raw[raw.startIndex..<idx] + "-" + raw[idx...]
    }
}
