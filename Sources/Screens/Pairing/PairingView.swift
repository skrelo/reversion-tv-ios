import SwiftUI

/// Pairing screen (§5) — the only entry point for an unauthenticated TV.
///
/// Brand lockup top-left; a white QR (encoding the RAW code, read directly
/// by the phone app's scanner) beside dual sign-in instructions; the big
/// gold code; and a live expiry countdown. The view model auto-mints a
/// fresh code on expiry / 410.
struct PairingView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var model = PairingViewModel()
    @State private var showExitConfirm = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bg.ignoresSafeArea()

            brandLockup
                .padding(.top, 60)
                .padding(.leading, 90)

            HStack(spacing: 90) {
                qrPanel
                infoPanel
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 120)
        }
        .onAppear { model.start { router.didAuthorize(token: $0) } }
        .onDisappear { model.stop() }
        .onExitCommand {
            showExitConfirm = true
        }
        .alert("Exit Reversion?", isPresented: $showExitConfirm) {
            Button("Exit", role: .destructive) { exit(0) }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to exit the app?")
        }
    }

    private var brandLockup: some View {
        HStack(spacing: 24) {
            Image("BrandMark")
                .resizable()
                .scaledToFit()
                .frame(height: 72)
            Image("BrandWordmark")
                .resizable()
                .scaledToFit()
                .frame(height: 44)
        }
    }

    private var qrPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(.white)
                .frame(width: 520, height: 520)
            if let qr = model.qr {
                Image(uiImage: qr)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
                    .frame(width: 456, height: 456)
            } else {
                ProgressView()
                    .scaleEffect(2)
            }
        }
    }

    private var infoPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Sign in to your TV")
                .font(.system(size: 54, weight: .bold))
                .foregroundStyle(Theme.text)
            Text("To sign in, choose one of:")
                .font(.system(size: 30))
                .foregroundStyle(Theme.textDim)

            VStack(alignment: .leading, spacing: 16) {
                step("①", "Scan the QR code with your phone camera.")
                step("②", AnyView(
                    HStack(spacing: 0) {
                        Text("Or on any browser, go to ")
                        Text("reversion.app/activate").foregroundStyle(Theme.gold)
                    }
                ))
            }
            .font(.system(size: 28))
            .foregroundStyle(Theme.text)

            Text("Then enter the code shown below")
                .font(.system(size: 26))
                .foregroundStyle(Theme.textDim)
                .padding(.top, 8)

            Text(PairingViewModel.format(model.code) .isEmpty ? "· · · ·" : PairingViewModel.format(model.code))
                .font(.system(size: 88, weight: .heavy, design: .monospaced))
                .foregroundStyle(Theme.gold)
                .kerning(4)

            if model.secondsLeft > 0, model.code != nil {
                Text("Expires in \(model.countdownText)")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.textDim)
            }
            if !model.status.isEmpty {
                Text(model.status)
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .frame(maxWidth: 760, alignment: .leading)
    }

    private func step(_ num: String, _ text: String) -> some View {
        step(num, AnyView(Text(text)))
    }

    private func step(_ num: String, _ content: AnyView) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(num).foregroundStyle(Theme.gold)
            content
        }
    }
}
