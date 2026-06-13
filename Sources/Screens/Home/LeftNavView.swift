import SwiftUI

/// Persistent left navigation (§6.6). Rendered as a **gradient overlay** on
/// top of the full-bleed content (mirrors Android TV / Tizen): the rail keeps
/// a fixed, narrow *layout* footprint (an icon strip) so it never pushes the
/// content, and its expanded panel + opaque→transparent gradient simply
/// overflow to the right, over the hero/rails, while any nav item holds focus.
struct LeftNavView: View {
    let activeId: String
    let profileName: String
    let profileHandle: String
    var profilePhotoUrl: String = ""
    @FocusState.Binding var focus: HomeFocus?
    let onSelect: (String) -> Void

    /// Fixed layout width — the collapsed icon strip. The expanded panel
    /// overflows past this without changing the layout (no content push).
    static let stripWidth: CGFloat = 132

    private var expanded: Bool {
        if case .nav = focus { return true }
        return false
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // Opaque→transparent gradient ONLY while the nav is open. When the
            // nav is closed there is NO gradient — the hero runs full-bleed and
            // the icons sit directly over the art (§6.6). When open it darkens
            // the panel so the labels/profile/brand lockup stay legible.
            if expanded {
                LinearGradient(
                    stops: [
                        .init(color: Theme.bg, location: 0.0),
                        .init(color: Theme.bg.opacity(0.9), location: 0.5),
                        .init(color: .clear, location: 1.0),
                    ],
                    startPoint: .leading, endPoint: .trailing
                )
                .frame(width: 560)
                .ignoresSafeArea()
            }

            inner
                .frame(width: expanded ? 340 : 80, alignment: .leading)
                .padding(.vertical, 60)
                // Android TV uses 18dp from the edge — match it (physical edge,
                // safe area ignored on .leading below).
                .padding(.leading, 18)
        }
        // Fixed layout footprint: focus geometry sees a narrow column on the
        // left, so content to its right stays reachable; visuals overflow.
        .frame(width: Self.stripWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        // Anchor to the PHYSICAL left edge (ignore the tvOS overscan safe-area
        // inset) so the icon strip hugs the edge like Android/Tizen instead of
        // floating ~60 pt in from the bezel.
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.22), value: expanded)
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: 0) {
            profile
                .opacity(expanded ? 1 : 0)
                .padding(.bottom, 24)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Nav.top) { item in navRow(item) }
            }

            Spacer(minLength: 0)

            navRow(Nav.settings)
                .opacity(expanded ? 1 : 0)

            // Full brand lockup (emblem + "THE REVERSION ARCHIVE"), matching
            // Android's bottom-of-rail logo. Hidden on the collapsed strip.
            Image("BrandLockup")
                .resizable().scaledToFit()
                .frame(height: 84)
                .opacity(expanded ? 0.95 : 0)
                .padding(.top, 28)
        }
    }

    private var profile: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().fill(Theme.gold.opacity(0.25))
                if let url = ImageURL.sized(profilePhotoUrl, width: 128), !profilePhotoUrl.isEmpty {
                    RemoteImage(url: url, contentMode: .fill, placeholder: .clear)
                        .clipShape(Circle())
                } else {
                    Text(String(profileName.prefix(1)).uppercased())
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(Theme.gold)
                }
            }
            .frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 2) {
                Text(profileName)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                if !profileHandle.isEmpty {
                    Text(profileHandle)
                        .font(.system(size: 18))
                        .foregroundStyle(Theme.textDim)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func navRow(_ item: NavItemSpec) -> some View {
        let isActive = item.id == activeId
        let isFocused = focus == .nav(item.id)
        return Button(action: { onSelect(item.id) }) {
            HStack(spacing: 22) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 30, weight: .medium))
                    .frame(width: 40)
                if expanded {
                    Text(item.label)
                        .font(.system(size: 24, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .foregroundStyle(isFocused ? Theme.bg : (isActive ? Theme.gold : Theme.textDim))
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? Theme.gold : .clear)
            )
        }
        .buttonStyle(NavButtonStyle())
        .focused($focus, equals: .nav(item.id))
    }
}

/// Nav rows draw their own focus background; this strips the default tvOS
/// button chrome (the white focus ring/panel) so only our pill shows.
struct NavButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}
