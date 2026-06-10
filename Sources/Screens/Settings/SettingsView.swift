import SwiftUI

/// Settings (§10). A 2-pane screen: left column = section tabs, right column =
/// the detail pane rebuilt per section. Focus follows the strict §10.6 contract
/// (RIGHT enters the pane / is consumed for display-only sections; LEFT returns
/// to the current section's tab; UP/DOWN move between tabs, stopping at the
/// last). The player's input model isn't reused here — this is ordinary SwiftUI
/// focus, steered with explicit `onMoveCommand` handlers.
struct SettingsView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = SettingsViewModel()
    @FocusState private var focus: SettingsFocus?
    @State private var section = "playback"
    @State private var legalOpen = false
    @State private var lastDoc = 0
    @State private var didInit = false

    private let sections: [(id: String, label: String, icon: String)] = [
        ("playback", "Playback", "play.circle.fill"),
        ("account", "Account", "person.crop.circle"),
        ("privacy", "Privacy", "lock.shield"),
        ("info", "Info", "info.circle"),
        ("signout", "Sign Out", "rectangle.portrait.and.arrow.right"),
    ]

    private var privacyDocs: [(slug: String, title: String)] {
        [("privacy-stewardship-notice", "Privacy & Data Stewardship Notice"),
         ("private-member-digital-agreement", "Private Member Digital Agreement")]
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Theme.bg.ignoresSafeArea()
            HStack(alignment: .top, spacing: 0) {
                tabsColumn
                    .frame(width: 420)
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                detailPane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .padding(.vertical, 80)
            .padding(.horizontal, 90)
        }
        .defaultFocus($focus, .tab("playback"))
        .task { await vm.loadAccount() }
        .onAppear { setInitialFocus() }
        .onChange(of: focus) { _, f in
            if case let .tab(id) = f { section = id }
        }
        // BACK closes the legal reader first; otherwise pops the screen.
        .onExitCommand {
            if legalOpen { closeLegal() }
            else if !router.path.isEmpty { router.path.removeLast() }
        }
    }

    // MARK: - Left: section tabs

    private var tabsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Settings")
                .font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.text)
                .padding(.leading, 20).padding(.bottom, 24)
            ForEach(sections, id: \.id) { tab in
                tabRow(tab)
            }
            Spacer()
        }
    }

    private func tabRow(_ tab: (id: String, label: String, icon: String)) -> some View {
        let isFocused = focus == .tab(tab.id)
        let isActive = section == tab.id
        return Button(action: { enterPane(tab.id) }) {
            HStack(spacing: 20) {
                Image(systemName: tab.icon).font(.system(size: 28)).frame(width: 36)
                Text(tab.label).font(.system(size: 28, weight: .medium))
                Spacer()
            }
            .foregroundStyle(isFocused ? Theme.bg : (isActive ? Theme.gold : Theme.textDim))
            .padding(.horizontal, 20).padding(.vertical, 16)
            .background(RoundedRectangle(cornerRadius: 12)
                .fill(isFocused ? Theme.gold : (isActive ? Color.white.opacity(0.08) : .clear)))
        }
        .buttonStyle(NavButtonStyle())
        .focused($focus, equals: .tab(tab.id))
        .onMoveCommand { dir in
            switch dir {
            case .up: moveTab(tab.id, by: -1)
            case .down: moveTab(tab.id, by: 1)
            case .right: enterPane(tab.id)
            default: break
            }
        }
    }

    // MARK: - Right: detail pane

    @ViewBuilder
    private var detailPane: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                switch section {
                case "playback": playbackPane
                case "account": accountPane
                case "privacy": privacyPane
                case "info": infoPane
                case "signout": signOutPane
                default: EmptyView()
                }
            }
            .padding(.leading, 56).padding(.trailing, 20).padding(.top, 70)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Playback — speed chips + autoplay toggle.
    private var playbackPane: some View {
        let sel = vm.selectedSpeedIndex()
        return VStack(alignment: .leading, spacing: 40) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Default Playback Speed")
                    .font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)
                HStack(spacing: 16) {
                    ForEach(Array(vm.speeds.enumerated()), id: \.offset) { i, v in
                        Button(action: { vm.setSpeed(v) }) {
                            Text(vm.speedLabel(v))
                                .font(.system(size: 24, weight: .semibold))
                                .foregroundStyle(focus == .speed(i) ? Theme.bg
                                    : (vm.speed == v ? Theme.gold : Theme.text))
                                .padding(.horizontal, 22).padding(.vertical, 14)
                                .background(RoundedRectangle(cornerRadius: 12)
                                    .fill(focus == .speed(i) ? Theme.gold
                                        : (vm.speed == v ? Color.white.opacity(0.14) : Color.white.opacity(0.06))))
                        }
                        .buttonStyle(NavButtonStyle())
                        .focusable(paneActive)
                        .focused($focus, equals: .speed(i))
                        .onMoveCommand { dir in
                            switch dir {
                            case .left: if i > 0 { focus = .speed(i - 1) } else { focus = .tab("playback") }
                            case .right: if i < vm.speeds.count - 1 { focus = .speed(i + 1) }
                            case .down: focus = .autoplay
                            default: break
                            }
                        }
                    }
                }
                Text("Applied when a video starts. You can still change speed during playback.")
                    .font(.system(size: 20)).foregroundStyle(Theme.textDim)
            }

            VStack(alignment: .leading, spacing: 14) {
                Button(action: { vm.toggleAutoplay() }) {
                    HStack {
                        Text("Autoplay Next").font(.system(size: 28, weight: .semibold))
                        Spacer()
                        Text(vm.autoplay ? "On" : "Off")
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(vm.autoplay ? Theme.bg : Theme.text)
                            .padding(.horizontal, 20).padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: 20)
                                .fill(vm.autoplay ? Theme.gold : Color.white.opacity(0.14)))
                    }
                    .foregroundStyle(focus == .autoplay ? Theme.bg : Theme.text)
                    .padding(.horizontal, 22).padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(focus == .autoplay ? Theme.gold : Color.white.opacity(0.06)))
                }
                .buttonStyle(NavButtonStyle())
                .focusable(paneActive)
                .focused($focus, equals: .autoplay)
                .frame(maxWidth: 760, alignment: .leading)
                .onMoveCommand { dir in
                    switch dir {
                    case .left: focus = .tab("playback")
                    case .up: focus = .speed(sel)
                    default: break
                    }
                }
                Text("Automatically advance to the next video when nearing the end.")
                    .font(.system(size: 20)).foregroundStyle(Theme.textDim)
            }
        }
    }

    // Account — display-only.
    private var accountPane: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Account").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)
            if vm.accountLoading {
                ProgressView().tint(Theme.text)
            } else {
                HStack(spacing: 24) {
                    ZStack {
                        Circle().fill(Theme.gold.opacity(0.25)).frame(width: 110, height: 110)
                        if let p = vm.user?.profilePhotoUrl, let url = ImageURL.sized(p, width: 220) {
                            RemoteImage(url: url).frame(width: 110, height: 110).clipShape(Circle())
                        } else {
                            Text(String((vm.user?.preferredLabel ?? "A").prefix(1)).uppercased())
                                .font(.system(size: 44, weight: .bold)).foregroundStyle(Theme.gold)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        infoRow("Name", vm.user?.preferredLabel ?? "—")
                        if let e = vm.user?.email, !e.isEmpty { infoRow("Email", e) }
                        if let m = vm.user?.memberSince, !m.isEmpty { infoRow("Member since", m) }
                    }
                }
            }
        }
    }

    // Privacy — two doc rows, or the in-app reader.
    @ViewBuilder
    private var privacyPane: some View {
        if legalOpen {
            legalReader
        } else {
            VStack(alignment: .leading, spacing: 18) {
                Text("Privacy").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)
                ForEach(Array(privacyDocs.enumerated()), id: \.offset) { i, doc in
                    Button(action: { openLegal(i) }) {
                        HStack {
                            Image(systemName: "doc.text").font(.system(size: 24))
                            Text(doc.title).font(.system(size: 26, weight: .medium))
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 20))
                        }
                        .foregroundStyle(focus == .doc(i) ? Theme.bg : Theme.text)
                        .padding(.horizontal, 22).padding(.vertical, 18)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(focus == .doc(i) ? Theme.gold : Color.white.opacity(0.06)))
                    }
                    .buttonStyle(NavButtonStyle())
                    .frame(maxWidth: 900, alignment: .leading)
                    .focusable(paneActive)
                    .focused($focus, equals: .doc(i))
                    .onMoveCommand { dir in
                        switch dir {
                        case .left: focus = .tab("privacy")
                        case .up: if i > 0 { focus = .doc(i - 1) }
                        case .down: if i < privacyDocs.count - 1 { focus = .doc(i + 1) }
                        default: break
                        }
                    }
                }
            }
        }
    }

    private var legalReader: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(vm.legalTitle).font(.system(size: 32, weight: .bold)).foregroundStyle(Theme.text)
            Text("Press BACK to return").font(.system(size: 18)).foregroundStyle(Theme.textDim)
            if vm.legalLoading {
                ProgressView().tint(Theme.text).padding(.top, 40)
            } else if let err = vm.legalError {
                Text(err).font(.system(size: 24)).foregroundStyle(Theme.textDim).padding(.top, 20)
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(vm.legalText)
                        .font(.system(size: 23)).foregroundStyle(Theme.text.opacity(0.95))
                        .lineSpacing(8)
                        .frame(maxWidth: 1100, alignment: .leading)
                        .padding(.trailing, 20)
                }
                .focusable(true)
                .focused($focus, equals: .reader)
            }
        }
    }

    // Info — display-only key/values.
    private var infoPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Info").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)
            infoRow("Platform", vm.platform)
            infoRow("Device Brand", vm.deviceBrand)
            infoRow("Device Model", vm.deviceModel)
            infoRow("OS Version", vm.osVersion)
            infoRow("App Version", vm.appVersion)
            infoRow("Build", vm.build)
            Text(vm.copyright)
                .font(.system(size: 20)).foregroundStyle(Theme.textDim)
                .padding(.top, 18)
        }
    }

    // Sign out — confirm + button.
    private var signOutPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Sign Out").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text)
            Text("You'll need to pair this TV again to sign back in.")
                .font(.system(size: 22)).foregroundStyle(Theme.textDim)
            Button(action: { router.signOut() }) {
                Text("Sign out")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(focus == .signOut ? Theme.bg : Theme.text)
                    .padding(.horizontal, 36).padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(focus == .signOut ? Theme.gold : Color.white.opacity(0.12)))
            }
            .buttonStyle(NavButtonStyle())
            .focusable(paneActive)
            .focused($focus, equals: .signOut)
            .onMoveCommand { dir in if dir == .left { focus = .tab("signout") } }
        }
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack(spacing: 16) {
            Text(key).font(.system(size: 22)).foregroundStyle(Theme.textDim).frame(width: 240, alignment: .leading)
            Text(value).font(.system(size: 22, weight: .medium)).foregroundStyle(Theme.text)
        }
    }

    // MARK: - Focus / nav

    private func setInitialFocus() {
        guard !didInit else { return }
        didInit = true
        DispatchQueue.main.async { focus = .tab("playback") }
    }

    /// Pane controls are focusable ONLY while focus already lives in the pane.
    /// While focus is on a tab, they're non-focusable so a geometric RIGHT has
    /// nothing to grab — `enterPane`'s explicit `focus =` is then the only focus
    /// change (no bottom-row geometric pick → no snap flicker). Because this is
    /// derived from `focus`, setting `focus = .doc(0)` flips it true in the same
    /// render pass, so the target is focusable exactly when it needs to be.
    private var paneActive: Bool {
        switch focus {
        case .tab, .none: return false
        default: return true
        }
    }

    private func moveTab(_ id: String, by delta: Int) {
        guard let idx = sections.firstIndex(where: { $0.id == id }) else { return }
        let next = idx + delta
        guard next >= 0, next < sections.count else { return }   // DOWN on last stops
        focus = .tab(sections[next].id)
    }

    /// RIGHT / OK on a tab: enter the detail pane at its first focusable, or
    /// consume for display-only sections (Account, Info) — never jump tabs.
    private func enterPane(_ id: String) {
        section = id
        switch id {
        case "playback": focus = .speed(vm.selectedSpeedIndex())
        case "privacy": focus = legalOpen ? .reader : .doc(0)
        case "signout": focus = .signOut
        default: break   // account/info: stay on the tab
        }
    }

    private func openLegal(_ index: Int) {
        lastDoc = index
        let doc = privacyDocs[index]
        vm.openLegal(doc.slug, fallbackTitle: doc.title)
        legalOpen = true
        DispatchQueue.main.async { focus = .reader }
    }

    private func closeLegal() {
        legalOpen = false
        vm.clearLegal()
        DispatchQueue.main.async { focus = .doc(lastDoc) }
    }
}

/// Settings focus space (§10.6). Section tabs + the per-section pane controls.
enum SettingsFocus: Hashable {
    case tab(String)
    case speed(Int)
    case autoplay
    case doc(Int)
    case signOut
    case reader
}
