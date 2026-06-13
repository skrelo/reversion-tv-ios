import SwiftUI

/// Drives the Pairing screen (§5): mint a code, render code + QR, count
/// down to expiry (auto-regenerating ~10 s before it lapses), and poll for
/// authorization. Mirrors the Tizen/Android flow 1:1.
@MainActor
final class PairingViewModel: ObservableObject {
    @Published var code: String?
    @Published var qr: UIImage?
    @Published var secondsLeft: Int = PairingViewModel.defaultTTL
    @Published var status: String = "Requesting code…"

    private static let defaultTTL = 300
    private static let defaultPollSeconds = 3
    private static let autoRefreshSeconds = 10

    private var pollSeconds = defaultPollSeconds
    private var currentCode: String?
    private var loopTask: Task<Void, Never>?

    /// Begin the pairing lifecycle. Idempotent restart on re-appearance.
    func start(onAuthorized: @escaping (String) -> Void) {
        stop()
        loopTask = Task { await runLifecycle(onAuthorized: onAuthorized) }
    }

    func stop() {
        loopTask?.cancel()
        loopTask = nil
    }

    /// Mid-dash the code for across-the-room legibility (matches Android).
    static func format(_ raw: String?) -> String {
        guard let raw, raw.count > 4 else { return raw ?? "" }
        let half = raw.count / 2
        let idx = raw.index(raw.startIndex, offsetBy: half)
        return raw[raw.startIndex..<idx] + "-" + raw[idx...]
    }

    var countdownText: String {
        let mm = secondsLeft / 60
        let ss = String(format: "%02d", max(0, secondsLeft % 60))
        return "\(mm):\(ss)"
    }

    // MARK: - Lifecycle

    private func runLifecycle(onAuthorized: @escaping (String) -> Void) async {
        while !Task.isCancelled {
            guard let minted = await mintCode() else {
                // Connection error — wait and retry the whole cycle.
                status = "Connection error — retrying…"
                try? await Task.sleep(nanoseconds: 5 * 1_000_000_000)
                continue
            }

            currentCode = minted.code
            pollSeconds = minted.pollInterval ?? Self.defaultPollSeconds
            code = minted.code
            status = ""
            // QR encodes the FULL activation URL (not the bare code) so a normal
            // phone camera lands on the web activate page with the code prefilled
            // (§5 — encoding the bare code only worked with the mobile app's
            // in-app scanner; an Amazon review rejection).
            qr = QRCodeGenerator.image(from: "https://reversion.app/activate?code=\(minted.code)")
            secondsLeft = minted.expiresIn ?? Self.defaultTTL

            let regenerate = await pollAndCountdown(onAuthorized: onAuthorized)
            if !regenerate { return } // authorized → stop the loop
        }
    }

    private func mintCode() async -> PairingCodeResponse? {
        status = "Requesting code…"
        code = nil
        qr = nil
        return try? await ApiClient.shared.requestPairingCode(deviceName: DeviceInfo.deviceName)
    }

    /// Runs the 1 s countdown + poll cadence for the current code.
    /// Returns true if the caller should regenerate (expiry / 410 / 404),
    /// false if authorized (lifecycle should end).
    private func pollAndCountdown(onAuthorized: @escaping (String) -> Void) async -> Bool {
        // First poll after ~1.5 s (§5).
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        var sinceLastPoll = 1.5

        while !Task.isCancelled {
            // Poll when due.
            if sinceLastPoll >= Double(pollSeconds), let c = currentCode {
                sinceLastPoll = 0
                do {
                    let res = try await ApiClient.shared.pollPairingCode(c)
                    if res.isAuthorized, let token = res.token {
                        onAuthorized(token)
                        return false
                    }
                } catch let error as ApiError {
                    if let s = error.status, s == 404 || s == 410 || s == 422 {
                        return true // expired/gone → regenerate
                    }
                    // transient — keep polling
                } catch {
                    // network/cancellation — keep polling
                }
            }

            // 1 s tick.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            if Task.isCancelled { return false }
            secondsLeft -= 1
            sinceLastPoll += 1

            if secondsLeft <= Self.autoRefreshSeconds {
                return true // auto-regenerate before lapse
            }
        }
        return false
    }
}
