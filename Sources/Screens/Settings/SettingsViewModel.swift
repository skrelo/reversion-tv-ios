import SwiftUI
import UIKit

/// Drives Settings (§10): mirrors prefs to/from `UserDefaults` (`Prefs`), loads
/// the account card from `GET /me`, and fetches legal documents on demand for
/// the in-app reader (§10.3). tvOS has no `WKWebView`, so the legal docs use the
/// JSON path (`GET /legal/{document}` → `{ title, html }`) rendered as text.
@MainActor
final class SettingsViewModel: ObservableObject {
    // Playback prefs (live-backed by Prefs/UserDefaults).
    @Published var speed: Double = Prefs.playbackSpeed
    @Published var autoplay: Bool = Prefs.autoplayNext

    // Account (GET /me).
    @Published var user: User?
    @Published var accountLoading = true

    // Legal reader.
    @Published var legalTitle = ""
    @Published var legalText = ""
    @Published var legalLoading = false
    @Published var legalError: String?

    /// The six speed options (§10.1).
    let speeds: [Double] = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    func speedLabel(_ v: Double) -> String {
        if v == 1.0 { return "Normal (1×)" }
        // Trim trailing zeros: 0.5 → "0.5×", 1.25 → "1.25×".
        let s = String(format: "%g", v)
        return "\(s)×"
    }

    func selectedSpeedIndex() -> Int { speeds.firstIndex(of: speed) ?? 2 }

    func setSpeed(_ v: Double) { speed = v; Prefs.playbackSpeed = v }
    func toggleAutoplay() { autoplay.toggle(); Prefs.autoplayNext = autoplay }

    func loadAccount() async {
        accountLoading = true
        user = (try? await ApiClient.shared.me())?.user
        accountLoading = false
    }

    /// Fetch + render a legal document into the reader (§10.3).
    func openLegal(_ document: String, fallbackTitle: String) {
        legalLoading = true
        legalError = nil
        legalTitle = fallbackTitle
        legalText = ""
        Task { [weak self] in
            guard let self else { return }
            do {
                let res = try await ApiClient.shared.legal(document: document)
                if let t = res.title, !t.isEmpty { self.legalTitle = t }
                self.legalText = Html.strip(res.html)
                if self.legalText.isEmpty { self.legalError = "This document is empty." }
            } catch {
                self.legalError = "Couldn't load this document."
            }
            self.legalLoading = false
        }
    }

    func clearLegal() {
        legalTitle = ""; legalText = ""; legalError = nil; legalLoading = false
    }

    // Info section (§10.4).
    var platform: String { "TV" }
    var deviceBrand: String { "Apple" }
    var deviceModel: String { UIDevice.current.model }   // "Apple TV"
    var osVersion: String { "tvOS \(UIDevice.current.systemVersion)" }
    var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
    var copyright: String {
        let year = Calendar.current.component(.year, from: Date())
        return "© \(year) Reversion. All rights reserved."
    }
}
