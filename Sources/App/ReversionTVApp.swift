import SwiftUI

@main
struct ReversionTVApp: App {
    @StateObject private var router = AppRouter()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(router)
                .preferredColorScheme(.dark)
        }
    }
}

/// Auth gate (§2): no token → Pairing; token → Home. Also listens for a
/// 401-driven sign-out (`.reversionUnauthorized`) to bounce back to Pairing.
struct RootView: View {
    @EnvironmentObject private var router: AppRouter

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch router.root {
            case .pairing:
                PairingView()
            case .home:
                NavigationStack(path: $router.path) {
                    HomeView()
                        .navigationDestination(for: Route.self) { route in
                            destination(for: route)
                        }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .reversionUnauthorized)) { _ in
            router.signOut()
        }
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case let .eventDetail(_, title):
            ScreenPlaceholder(title: title ?? "Event", subtitle: "Event Detail (§7) lands next.")
        case let .player(videoId):
            ScreenPlaceholder(title: "Player", subtitle: "Video #\(videoId) — Player (§9) lands next.")
        case .search:
            ScreenPlaceholder(title: "Search", subtitle: "Search (§8) lands next.")
        case .settings:
            ScreenPlaceholder(title: "Settings", subtitle: "Settings (§10) lands next.")
        }
    }
}

/// Temporary stand-in for screens not yet built.
struct ScreenPlaceholder: View {
    let title: String
    let subtitle: String

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 24) {
                Text(title)
                    .font(.system(size: 64, weight: .bold))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 30))
                    .foregroundStyle(Theme.textDim)
            }
        }
    }
}
