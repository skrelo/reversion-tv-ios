import SwiftUI

/// My Notes (§11). Two-pane browse over the user's notes: left = video groups,
/// right = the focused group's notes (header "Play from start" + note rows).
/// SELECT a note → Player seeked to its timecode; RIGHT on a note → its trash
/// button → confirm modal → delete. Single manual focus space with the same
/// focusable-gating model proven in Settings (§10.6) so RIGHT into the pane
/// never snap-flickers. BACK pops to Home (closes the modal first).
struct MyNotesView: View {
    @EnvironmentObject private var router: AppRouter
    @StateObject private var vm = MyNotesViewModel()
    @FocusState private var focus: MyNotesFocus?

    /// Group index whose notes the right pane shows; tracks the focused row.
    @State private var selected = 0
    @State private var pendingDelete: PendingDelete?
    @State private var didInit = false

    private var modalOpen: Bool { pendingDelete != nil }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            content
            if let pd = pendingDelete {
                deleteModal(pd)
            }
        }
        .task { await vm.initialLoadIfNeeded(); arriveInitialFocus() }
        .onAppear { vm.refreshOnReturn() }
        .onChange(of: focus) { _, f in
            if case let .group(i) = f { selected = i }
        }
        .onExitCommand {
            if modalOpen { cancelDelete() }
            else if !router.path.isEmpty { router.path.removeLast() }
        }
    }

    // MARK: - States

    @ViewBuilder
    private var content: some View {
        if vm.loading {
            ProgressView().scaleEffect(2).tint(Theme.text)
        } else if let err = vm.error, vm.groups.isEmpty {
            errorState(err)
        } else if vm.groups.isEmpty {
            emptyState
        } else {
            twoPane
        }
    }

    private func errorState(_ msg: String) -> some View {
        VStack(spacing: 28) {
            Image(systemName: "exclamationmark.triangle").font(.system(size: 60)).foregroundStyle(Theme.textDim)
            Text(msg).font(.system(size: 30)).foregroundStyle(Theme.text)
            Button(action: { Task { @MainActor in await vm.load(); arriveInitialFocus() } }) {
                Text("Retry").font(.system(size: 26, weight: .bold))
                    .foregroundStyle(focus == .retry ? Theme.bg : Theme.text)
                    .padding(.horizontal, 40).padding(.vertical, 16)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(focus == .retry ? Theme.gold : Color.white.opacity(0.12)))
            }
            .buttonStyle(NavButtonStyle())
            .focused($focus, equals: .retry)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            Image(systemName: "square.and.pencil").font(.system(size: 64)).foregroundStyle(Theme.gold.opacity(0.7))
            Text("No notes yet").font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.text)
            Text("Add notes while watching a video and they'll appear here.")
                .font(.system(size: 24)).foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center).frame(maxWidth: 640)
            Button(action: { if !router.path.isEmpty { router.path.removeLast() } }) {
                Text("Back to Home").font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(focus == .empty ? Theme.bg : Theme.text)
                    .padding(.horizontal, 36).padding(.vertical, 14)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(focus == .empty ? Theme.gold : Color.white.opacity(0.12)))
            }
            .buttonStyle(NavButtonStyle())
            .focused($focus, equals: .empty)
            .padding(.top, 8)
        }
    }

    // MARK: - Two-pane

    private var twoPane: some View {
        HStack(alignment: .top, spacing: 0) {
            groupsColumn.frame(width: 600)
            Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
            notesColumn.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.vertical, 70).padding(.horizontal, 80)
    }

    // Left: video groups.
    private var groupsColumn: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("My Notes").font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.text)
                .padding(.leading, 16).padding(.bottom, 18)
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(vm.groups.enumerated()), id: \.element.id) { i, g in
                            groupRow(i, g).id(i)
                        }
                    }
                }
                .onChange(of: selected) { _, i in
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(i, anchor: .center) }
                }
            }
        }
    }

    private func groupRow(_ i: Int, _ g: MyNotesGroup) -> some View {
        let isFocused = focus == .group(i)
        let isSelected = selected == i
        return Button(action: { if selected == i { enterNotes() } else { focus = .group(i) } }) {
            HStack(spacing: 16) {
                poster(g.posterUrl, w: 96, h: 96)
                VStack(alignment: .leading, spacing: 4) {
                    Text(g.videoTitle ?? "Untitled").font(.system(size: 24, weight: .semibold))
                        .lineLimit(1)
                    if let e = g.eventTitle, !e.isEmpty {
                        Text(e).font(.system(size: 19)).foregroundStyle(isFocused ? Theme.bg.opacity(0.8) : Theme.textDim).lineLimit(1)
                    }
                    Text(metaLine(g)).font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isFocused ? Theme.bg.opacity(0.8) : Theme.gold)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(isFocused ? Theme.bg : Theme.text)
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(isFocused ? Theme.gold : (isSelected ? Color.white.opacity(0.08) : .clear)))
        }
        .buttonStyle(NavButtonStyle())
        .focusable(!modalOpen)
        .focused($focus, equals: .group(i))
        .onMoveCommand { dir in
            switch dir {
            case .up: if i > 0 { focus = .group(i - 1) }
            case .down: if i < vm.groups.count - 1 { focus = .group(i + 1) }
            case .right: enterNotes()
            default: break
            }
        }
    }

    // Right: focused group's notes.
    @ViewBuilder
    private var notesColumn: some View {
        if vm.groups.indices.contains(selected) {
            let g = vm.groups[selected]
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        notesHeader(g)
                        ForEach(Array((g.notes ?? []).enumerated()), id: \.element.id) { i, n in
                            noteRow(i, n, group: g).id("note\(i)")
                        }
                    }
                    .padding(.leading, 48).padding(.trailing, 12).padding(.top, 64)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: focus) { _, f in
                    if case let .note(i) = f { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("note\(i)", anchor: .center) } }
                    if case let .noteDelete(i) = f { withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("note\(i)", anchor: .center) } }
                }
            }
        }
    }

    private func notesHeader(_ g: MyNotesGroup) -> some View {
        HStack(spacing: 20) {
            poster(g.posterUrl, w: 120, h: 120)
            VStack(alignment: .leading, spacing: 8) {
                Text(g.videoTitle ?? "Untitled").font(.system(size: 30, weight: .bold)).foregroundStyle(Theme.text).lineLimit(2)
                if let e = g.eventTitle, !e.isEmpty {
                    Text(e).font(.system(size: 20)).foregroundStyle(Theme.textDim).lineLimit(1)
                }
                Button(action: { playFromStart(g) }) {
                    HStack(spacing: 10) {
                        Image(systemName: "play.fill").font(.system(size: 20))
                        Text("Play video").font(.system(size: 22, weight: .semibold))
                    }
                    .foregroundStyle(focus == .playFromStart ? Theme.bg : Theme.text)
                    .padding(.horizontal, 24).padding(.vertical, 12)
                    .background(RoundedRectangle(cornerRadius: 10)
                        .fill(focus == .playFromStart ? Theme.gold : Color.white.opacity(0.12)))
                }
                .buttonStyle(NavButtonStyle())
                .focusable(paneActive)
                .focused($focus, equals: .playFromStart)
                .onMoveCommand { dir in
                    switch dir {
                    case .left: focus = .group(selected)
                    case .down: if !(g.notes ?? []).isEmpty { focus = .note(0) }
                    default: break
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
    }

    private func noteRow(_ i: Int, _ n: MyNote, group g: MyNotesGroup) -> some View {
        let isFocused = focus == .note(i)
        let delFocused = focus == .noteDelete(i)
        let last = (g.notes?.count ?? 1) - 1
        return HStack(spacing: 14) {
            Button(action: { jumpTo(g, n) }) {
                HStack(alignment: .center, spacing: 16) {
                    Text(n.timecode ?? "0:00").font(.system(size: 20, weight: .bold, design: .monospaced))
                        .foregroundStyle(isFocused ? Theme.bg : Theme.gold)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(RoundedRectangle(cornerRadius: 8)
                            .fill(isFocused ? Theme.bg.opacity(0.18) : Theme.gold.opacity(0.15)))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(n.title ?? "Note").font(.system(size: 23, weight: .semibold)).lineLimit(1)
                        if let ex = n.excerpt, !ex.isEmpty {
                            Text(ex).font(.system(size: 19))
                                .foregroundStyle(isFocused ? Theme.bg.opacity(0.85) : Theme.textDim)
                                .lineLimit(2).multilineTextAlignment(.leading)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "play.circle").font(.system(size: 24))
                        .foregroundStyle(isFocused ? Theme.bg.opacity(0.7) : Theme.textDim)
                }
                .foregroundStyle(isFocused ? Theme.bg : Theme.text)
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 12)
                    .fill(isFocused ? Theme.gold : Color.white.opacity(0.05)))
            }
            .buttonStyle(NavButtonStyle())
            .focusable(paneActive)
            .focused($focus, equals: .note(i))
            .onMoveCommand { dir in
                switch dir {
                case .left: focus = .group(selected)
                case .right: focus = .noteDelete(i)
                case .up: focus = i > 0 ? .note(i - 1) : .playFromStart
                case .down: if i < last { focus = .note(i + 1) }
                default: break
                }
            }

            Button(action: { askDelete(g, n) }) {
                Image(systemName: "trash").font(.system(size: 22))
                    .foregroundStyle(delFocused ? Theme.bg : Theme.textDim)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12)
                        .fill(delFocused ? Theme.gold : Color.white.opacity(0.05)))
            }
            .buttonStyle(NavButtonStyle())
            .focusable(paneActive)
            .focused($focus, equals: .noteDelete(i))
            .onMoveCommand { dir in
                switch dir {
                case .left: focus = .note(i)
                case .up: if i > 0 { focus = .noteDelete(i - 1) }
                case .down: if i < last { focus = .noteDelete(i + 1) }
                default: break
                }
            }
        }
    }

    // MARK: - Delete confirm modal (§11.4)

    private func deleteModal(_ pd: PendingDelete) -> some View {
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 22) {
                Text("Delete this note?").font(.system(size: 34, weight: .bold)).foregroundStyle(Theme.text)
                VStack(spacing: 6) {
                    if let tc = pd.note.timecode { Text(tc).font(.system(size: 22, weight: .bold, design: .monospaced)).foregroundStyle(Theme.gold) }
                    Text(pd.note.title ?? "Note").font(.system(size: 24, weight: .semibold)).foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.center)
                }
                Text("This can't be undone.").font(.system(size: 20)).foregroundStyle(Theme.textDim)
                HStack(spacing: 20) {
                    Button(action: { cancelDelete() }) {
                        Text("Cancel").font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(focus == .cancelDelete ? Theme.bg : Theme.text)
                            .padding(.horizontal, 40).padding(.vertical, 16)
                            .background(RoundedRectangle(cornerRadius: 12)
                                .fill(focus == .cancelDelete ? Theme.gold : Color.white.opacity(0.14)))
                    }
                    .buttonStyle(NavButtonStyle())
                    .focusable(modalOpen)
                    .focused($focus, equals: .cancelDelete)
                    .onMoveCommand { if $0 == .right { focus = .confirmDelete } }

                    Button(action: { confirmDelete(pd) }) {
                        HStack(spacing: 8) {
                            if vm.deleting { ProgressView().tint(Theme.text) }
                            Text("Delete").font(.system(size: 24, weight: .bold))
                        }
                        .foregroundStyle(focus == .confirmDelete ? .white : Color(red: 0.9, green: 0.4, blue: 0.4))
                        .padding(.horizontal, 40).padding(.vertical, 16)
                        .background(RoundedRectangle(cornerRadius: 12)
                            .fill(focus == .confirmDelete ? Color(red: 0.78, green: 0.22, blue: 0.22) : Color.white.opacity(0.10)))
                    }
                    .buttonStyle(NavButtonStyle())
                    .focusable(modalOpen)
                    .focused($focus, equals: .confirmDelete)
                    .onMoveCommand { if $0 == .left { focus = .cancelDelete } }
                }
                .padding(.top, 8)
            }
            .padding(48)
            .frame(maxWidth: 720)
            .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
        }
    }

    // MARK: - Helpers

    private func poster(_ url: String?, w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08))
            if let u = ImageURL.sized(url, width: Int(w * 2)) {
                RemoteImage(url: u, contentMode: .fill, placeholder: .clear)
            } else {
                Image(systemName: "film").font(.system(size: w * 0.3)).foregroundStyle(Theme.textDim)
            }
        }
        .frame(width: w, height: h).clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func metaLine(_ g: MyNotesGroup) -> String {
        let n = g.count
        var s = "\(n) note\(n == 1 ? "" : "s")"
        if let d = g.sessionDate, !d.isEmpty { s += " · \(d)" }
        return s
    }

    /// `paneActive` derives from focus so the right-pane controls are focusable
    /// ONLY while focus already lives there — a geometric RIGHT from a group row
    /// has nothing to grab and `enterNotes`'s explicit set is the only move (no
    /// snap flicker). Same trick as Settings §10.6.
    private var paneActive: Bool {
        switch focus {
        case .playFromStart, .note, .noteDelete: return true
        default: return false
        }
    }

    private func arriveInitialFocus() {
        guard !didInit, !vm.groups.isEmpty else {
            if vm.groups.isEmpty { DispatchQueue.main.async { focus = vm.error != nil ? .retry : .empty } }
            return
        }
        didInit = true
        selected = 0
        DispatchQueue.main.async { focus = .group(0) }
    }

    private func enterNotes() {
        guard vm.groups.indices.contains(selected) else { return }
        let notes = vm.groups[selected].notes ?? []
        focus = notes.isEmpty ? .playFromStart : .note(0)
    }

    private func jumpTo(_ g: MyNotesGroup, _ n: MyNote) {
        router.push(.playerAt(videoId: g.videoId, seconds: n.seconds ?? 0))
    }

    private func playFromStart(_ g: MyNotesGroup) {
        router.push(.player(videoId: g.videoId))
    }

    private func askDelete(_ g: MyNotesGroup, _ n: MyNote) {
        pendingDelete = PendingDelete(videoId: g.videoId, note: n)
        DispatchQueue.main.async { focus = .cancelDelete }
    }

    private func cancelDelete() {
        let target = pendingDelete
        pendingDelete = nil
        // Restore focus to the trash button of the note we were about to delete.
        if let t = target, vm.groups.indices.contains(selected),
           let idx = (vm.groups[selected].notes ?? []).firstIndex(where: { $0.id == t.note.id }) {
            DispatchQueue.main.async { focus = .noteDelete(idx) }
        }
    }

    private func confirmDelete(_ pd: PendingDelete) {
        Task { @MainActor in
            let ok = await vm.deleteNote(videoId: pd.videoId, noteId: pd.note.id)
            pendingDelete = nil
            guard ok else { return }
            restoreFocusAfterDelete()
        }
    }

    /// After a successful delete, land focus sensibly: stay on the same group's
    /// notes if any remain, else move to the neighbouring group, else empty.
    private func restoreFocusAfterDelete() {
        if vm.groups.isEmpty {
            DispatchQueue.main.async { focus = .empty }
            return
        }
        if selected >= vm.groups.count { selected = vm.groups.count - 1 }
        let notes = vm.groups[selected].notes ?? []
        DispatchQueue.main.async {
            focus = notes.isEmpty ? .group(selected) : .note(0)
        }
    }
}

/// A note queued for deletion (drives the confirm modal, §11.4).
struct PendingDelete: Identifiable {
    let videoId: Int
    let note: MyNote
    var id: Int { note.id }
}

/// Single manual focus space for My Notes (§11.3). Left groups + right pane
/// (header action, note rows, per-note trash) + modal + state placeholders.
enum MyNotesFocus: Hashable {
    case group(Int)
    case playFromStart
    case note(Int)
    case noteDelete(Int)
    case cancelDelete
    case confirmDelete
    case retry
    case empty
}
