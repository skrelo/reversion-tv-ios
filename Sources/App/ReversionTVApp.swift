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
            case .welcome:
                WelcomeView()
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
        case let .eventDetail(id, title):
            EventDetailView(eventId: id, title: title)
        case let .player(videoId):
            PlayerView(videoId: videoId)
        case .search:
            SearchView()
        case .settings:
            SettingsView()
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
