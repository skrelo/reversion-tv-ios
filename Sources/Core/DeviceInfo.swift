import UIKit

/// Device descriptors used for pairing (`device_name`, §5) and the
/// Settings → Info pane (§10.4).
enum DeviceInfo {
    /// Human label sent to `device-auth/request`, e.g. "Apple TV".
    static var deviceName: String {
        let name = UIDevice.current.name
        return name.isEmpty ? "Apple TV" : name
    }

    static var brand: String { "Apple" }
    static var model: String { UIDevice.current.model }
    static var osVersion: String { "tvOS \(UIDevice.current.systemVersion)" }

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
