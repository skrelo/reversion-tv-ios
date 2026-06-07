import SwiftUI

/// Top-level navigation state. For now this is a small auth gate (Pairing
/// vs Home); pushes for Event Detail / Player / Search / Settings will be
/// added with their screens in later passes.
/// A pushed screen on top of Home.
enum Route: Hashable {
    case eventDetail(id: Int, title: String?)
    case player(videoId: Int)
    case search
    case settings
}

@MainActor
final class AppRouter: ObservableObject {
    enum Root { case pairing, home }

    @Published var root: Root
    /// Navigation stack on top of Home (Event Detail / Player / Search / Settings).
    @Published var path: [Route] = []

    init() {
        root = KeychainTokenStore.isLoggedIn ? .home : .pairing
    }

    func push(_ route: Route) { path.append(route) }
    func popToRoot() { path.removeAll() }

    /// Pairing succeeded — persist token, go Home (§5).
    func didAuthorize(token: String) {
        KeychainTokenStore.save(token)
        path.removeAll()
        root = .home
    }

    /// Clear token + non-token prefs, return to Pairing (§5, §10.5).
    func signOut() {
        KeychainTokenStore.clear()
        Prefs.clear()
        path.removeAll()
        root = .pairing
    }
}
