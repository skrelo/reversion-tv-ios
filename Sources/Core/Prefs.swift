import Foundation

/// Persisted user preferences (§11). Backed by `UserDefaults`.
///
/// The auth *token* is intentionally NOT stored here — it lives in the
/// Keychain (`KeychainTokenStore`) per the "secure token storage" MVP
/// requirement (§2). Everything else (playback speed, autoplay, pop-up
/// toggles) is non-sensitive and lives in `UserDefaults`.
enum Prefs {
    private static let store = UserDefaults.standard

    enum Key {
        static let playbackSpeed = "player.defaultSpeed"
        static let autoplayNext = "player.autoplayNext"
        static let annotationPopups = "player.annotationPopups"
        static let notePopups = "player.notePopups"
    }

    /// Default speed applied at video start (§10.1). Default 1.0.
    static var playbackSpeed: Double {
        get { store.object(forKey: Key.playbackSpeed) as? Double ?? 1.0 }
        set { store.set(newValue, forKey: Key.playbackSpeed) }
    }

    /// Up-Next auto-advance gate (§9.12). Default true.
    static var autoplayNext: Bool {
        get { store.object(forKey: Key.autoplayNext) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.autoplayNext) }
    }

    /// In-player annotation pop-up toggle (§9.11). Default true.
    static var annotationPopups: Bool {
        get { store.object(forKey: Key.annotationPopups) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.annotationPopups) }
    }

    /// In-player note pop-up toggle (§9.11). Default true.
    static var notePopups: Bool {
        get { store.object(forKey: Key.notePopups) as? Bool ?? true }
        set { store.set(newValue, forKey: Key.notePopups) }
    }

    /// Wipe non-token prefs (used alongside token clear on sign-out).
    static func clear() {
        [Key.playbackSpeed, Key.autoplayNext, Key.annotationPopups, Key.notePopups]
            .forEach { store.removeObject(forKey: $0) }
    }
}
