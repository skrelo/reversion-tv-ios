import SwiftUI

/// Top-level navigation state. For now this is a small auth gate (Pairing
/// vs Home); pushes for Event Detail / Player / Search / Settings will be
/// added with their screens in later passes.
/// A pushed screen on top of Home.
enum Route: Hashable {
    case eventDetail(id: Int, title: String?)
    case player(videoId: Int)
    /// Player opened at a specific timecode (jump-to-note from My Notes, §11.4).
    case playerAt(videoId: Int, seconds: Int)
    case search
    case settings
    case myNotes
}

@MainActor
final class AppRouter: ObservableObject {
    enum Root { case welcome, pairing, home }

    @Published var root: Root
    /// Navigation stack on top of Home (Event Detail / Player / Search / Settings).
    @Published var path: [Route] = []

    init() {
        root = KeychainTokenStore.isLoggedIn ? .home : .welcome
    }

    func push(_ route: Route) { path.append(route) }
    func popToRoot() { path.removeAll() }

    /// Welcome → Pairing (§5).
    func goToPairing() {
        root = .pairing
    }

    /// Pairing succeeded — persist token, go Home (§5).
    func didAuthorize(token: String) {
        KeychainTokenStore.save(token)
        path.removeAll()
        root = .home
    }

    /// Clear token + non-token prefs, return to Welcome (§5).
    func signOut() {
        KeychainTokenStore.clear()
        Prefs.clear()
        path.removeAll()
        root = .welcome
    }
}
