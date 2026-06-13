import SwiftUI

/// Welcome / guest landing screen (§5). Shown on every unauthenticated launch
/// before the pairing screen — mirrors major streaming apps instead of dropping
/// the user straight onto the pairing code. Sign-out also returns here.
struct WelcomeView: View {
    @EnvironmentObject private var router: AppRouter

    enum WelcomeFocus { case signIn, exit }
    @FocusState private var focus: WelcomeFocus?
    @State private var showExitConfirm = false

    var body: some View {
        ZStack {
            // Background — shared welcome/hero backdrop (§5). Local asset so it
            // works logged-out (there is no API image to pull pre-auth).
            Color(red: 0.04, green: 0.06, blue: 0.12).ignoresSafeArea()

            Image("HomeBackdrop")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .clipped()

            // Navy darken + left scrim so copy on the left stays legible.
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.15), location: 0),
                    .init(color: Color.black.opacity(0.35), location: 0.5),
                    .init(color: Color.black.opacity(0.7), location: 1),
                ],
                startPoint: .trailing, endPoint: .leading
            )
            .ignoresSafeArea()

            // Left-column content
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Spacer()

                    HStack(spacing: 32) {
                        Image("BrandMark")
                            .resizable().scaledToFit()
                            .frame(height: 140)
                        Image("BrandWordmark")
                            .resizable().scaledToFit()
                            .frame(height: 88)
                    }
                    .padding(.bottom, 44)

                    Text("Welcome")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(Theme.text)

                    Text("Watch your meetup and livestream library on TV.")
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.textDim)
                        .padding(.top, 14)

                    Text("Access is for members only. Sign up or manage your account at reversion.app.")
                        .font(.system(size: 24))
                        .foregroundStyle(Theme.textDim.opacity(0.7))
                        .padding(.top, 10)
                        .frame(maxWidth: 680, alignment: .leading)

                    HStack(spacing: 24) {
                        welcomeButton("Sign In", primary: true, focused: focus == .signIn) {
                            router.goToPairing()
                        }
                        .focused($focus, equals: .signIn)

                        welcomeButton("Exit", primary: false, focused: focus == .exit) {
                            showExitConfirm = true
                        }
                        .focused($focus, equals: .exit)
                    }
                    .padding(.top, 52)

                    Spacer()
                }
                .padding(.leading, 120)
                .frame(maxWidth: 860, alignment: .leading)

                Spacer()
            }
        }
        .onAppear { focus = .signIn }
        .onExitCommand { showExitConfirm = true }
        .onMoveCommand { dir in
            switch dir {
            case .left:  focus = .signIn
            case .right: focus = .exit
            default: break
            }
        }
        .alert("Exit Reversion?", isPresented: $showExitConfirm) {
            Button("Exit", role: .destructive) { exit(0) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to exit the app?")
        }
    }

    private func welcomeButton(_ label: String, primary: Bool, focused: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(focused ? Theme.bg : (primary ? Theme.gold : Theme.text))
                .padding(.horizontal, 52).padding(.vertical, 20)
                .background(
                    focused
                        ? (primary ? Theme.gold : Theme.text)
                        : (primary ? Theme.gold.opacity(0.2) : Color.white.opacity(0.12))
                )
                .cornerRadius(14)
        }
        .buttonStyle(PlainWelcomeButtonStyle())
    }


}

/// Strips ALL default tvOS button chrome (focus ring, highlight panel, etc.).
private struct PlainWelcomeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
