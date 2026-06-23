import SwiftUI

/// Data + actions for the My Notes screen (§11). Read-only browse over
/// `GET /my-notes` (grouped by video, presentation-ready) plus per-note delete
/// via `DELETE /videos/{id}/notes/{note}`. Note creation/editing stays in the
/// Player (§9.7) — this screen only finds, jumps to, and deletes notes.
@MainActor
final class MyNotesViewModel: ObservableObject {
    @Published var groups: [MyNotesGroup] = []
    @Published var loading = true
    @Published var error: String?
    /// Set while a delete is in flight so the confirm modal can show progress
    /// and the row can't be double-deleted.
    @Published var deleting = false

    private(set) var loaded = false

    /// First entry only — load with a spinner. Re-entry uses `refreshOnReturn`.
    func initialLoadIfNeeded() async {
        guard !loaded else { return }
        await load()
    }

    /// Initial load (spinner) + silent re-fetch on return. Re-fetching keeps the
    /// list honest after a note was added/deleted in the Player (§11.1).
    func load(silent: Bool = false) async {
        if !silent { loading = true }
        error = nil
        do {
            let res = try await ApiClient.shared.myNotes()
            groups = res.data ?? []
        } catch {
            if (error as? ApiError)?.status == 401 { return } // handled globally
            if groups.isEmpty { self.error = "Could not load your notes." }
        }
        loading = false
        loaded = true
    }

    /// Re-fetch when the user lands back on the screen (e.g. returned from the
    /// Player) — silent so the list doesn't flash a spinner.
    func refreshOnReturn() {
        guard loaded else { return }
        Task { await load(silent: true) }
    }

    /// Delete one note. Optimistic: remove it (and the whole group if it was the
    /// last) immediately; restore on failure (§11.4).
    func deleteNote(videoId: Int, noteId: Int) async -> Bool {
        guard !deleting else { return false }
        deleting = true
        defer { deleting = false }

        // Snapshot for rollback.
        let snapshot = groups
        applyLocalDelete(videoId: videoId, noteId: noteId)

        do {
            try await ApiClient.shared.deleteNote(videoId: videoId, noteId: noteId)
            return true
        } catch {
            if (error as? ApiError)?.status == 401 { return false }
            groups = snapshot   // restore
            self.error = "Could not delete that note. Try again."
            return false
        }
    }

    private func applyLocalDelete(videoId: Int, noteId: Int) {
        guard let gi = groups.firstIndex(where: { $0.videoId == videoId }) else { return }
        var notes = groups[gi].notes ?? []
        notes.removeAll { $0.id == noteId }
        if notes.isEmpty {
            groups.remove(at: gi)
        } else {
            let g = groups[gi]
            groups[gi] = MyNotesGroup(
                videoId: g.videoId, videoTitle: g.videoTitle, sessionDate: g.sessionDate,
                eventId: g.eventId, eventTitle: g.eventTitle, posterUrl: g.posterUrl,
                cardPosterUrl: g.cardPosterUrl, notesCount: notes.count,
                latestNoteAt: g.latestNoteAt, notes: notes
            )
        }
    }
}
