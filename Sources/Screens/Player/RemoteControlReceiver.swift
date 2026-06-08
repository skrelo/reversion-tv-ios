import SwiftUI
import UIKit

/// Logical remote keys (§9). Maps the Siri-remote / D-pad press types to the
/// same vocabulary the Tizen/Android handlers use.
enum RemoteKey {
    case up, down, left, right, select, menu, playPause
}

/// Full-screen UIKit press capture that drives the custom player chrome.
///
/// The player owns focus and key handling end-to-end (§9) — exactly like the
/// Tizen window-level keydown handler and Android `dispatchKeyEvent`. SwiftUI's
/// geometric focus engine is the wrong tool here (zones, hold-to-seek, modal
/// state machine, Netflix double-back), so this is the single focusable view;
/// it keeps focus and forwards raw press began/ended events.
///
/// `onKeyDown` returns whether it consumed the press. Menu/BACK is intentionally
/// NOT mapped here — it bubbles to SwiftUI's `.onExitCommand` on the player view,
/// which is the only thing that reliably suppresses the `NavigationStack` pop.
struct RemoteControlReceiver: UIViewControllerRepresentable {
    var onKeyDown: (RemoteKey) -> Bool
    var onKeyUp: (RemoteKey) -> Void = { _ in }

    func makeUIViewController(context: Context) -> PressCaptureController {
        let vc = PressCaptureController()
        vc.onKeyDown = onKeyDown
        vc.onKeyUp = onKeyUp
        return vc
    }

    func updateUIViewController(_ vc: PressCaptureController, context: Context) {
        vc.onKeyDown = onKeyDown
        vc.onKeyUp = onKeyUp
    }
}

final class PressCaptureController: UIViewController {
    var onKeyDown: ((RemoteKey) -> Bool)?
    var onKeyUp: ((RemoteKey) -> Void)?
    /// Presses we consumed in `pressesBegan` — must NOT be forwarded to `super`
    /// on end/cancel either, or the system may act on them. Tracked per-press so
    /// the matching end is suppressed. (BACK/Menu is not handled here at all — it
    /// bubbles to SwiftUI's `.onExitCommand`.)
    private var consumed = Set<UIPress>()

    override func loadView() {
        let v = PressCaptureView()
        v.backgroundColor = .clear
        view = v
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] { [view] }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        setNeedsFocusUpdate()
        updateFocusIfNeeded()
    }

    private func map(_ type: UIPress.PressType) -> RemoteKey? {
        switch type {
        case .upArrow: return .up
        case .downArrow: return .down
        case .leftArrow: return .left
        case .rightArrow: return .right
        case .select: return .select
        // Menu/BACK is handled by SwiftUI `.onExitCommand` on the player view —
        // that's the only thing that reliably suppresses the NavigationStack's
        // default pop. Returning nil here lets the press bubble up to it.
        case .playPause: return .playPause
        default: return nil
        }
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passthrough: Set<UIPress> = []
        for press in presses {
            guard let key = map(press.type), let onKeyDown else { passthrough.insert(press); continue }
            if onKeyDown(key) { consumed.insert(press) } else { passthrough.insert(press) }
        }
        if !passthrough.isEmpty { super.pressesBegan(passthrough, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passthrough: Set<UIPress> = []
        for press in presses {
            if let key = map(press.type) { onKeyUp?(key) }
            if consumed.remove(press) == nil { passthrough.insert(press) }
        }
        if !passthrough.isEmpty { super.pressesEnded(passthrough, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var passthrough: Set<UIPress> = []
        for press in presses {
            if let key = map(press.type) { onKeyUp?(key) }
            if consumed.remove(press) == nil { passthrough.insert(press) }
        }
        if !passthrough.isEmpty { super.pressesCancelled(passthrough, with: event) }
    }
}

/// The single focusable surface; keeps focus so all presses route to the VC.
final class PressCaptureView: UIView {
    override var canBecomeFocused: Bool { true }
}
