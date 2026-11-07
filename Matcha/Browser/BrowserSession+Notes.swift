import Foundation
import Observation

/// Notes shown in tabs (task 12.5): each one carries its note's title, also when the note is renamed elsewhere (the
/// library, another window, sync).
extension BrowserSession {
    /// Follows the notes and the tabs: the titles are given again at each change.
    func observeNoteTitles() {
        withObservationTracking {
            updateNoteTabTitles()
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeNoteTitles() }
        }
    }

    private func updateNoteTabTitles() {
        let titles = Dictionary(notes.notes.map { ($0.id, $0.title) }) { first, _ in first }
        let tabs = spaces.flatMap(\.tabManager.tabs) + windowTabs.flatMap(\.tabManager.tabs)
        for tab in tabs {
            guard let id = tab.noteID, let title = titles[id] else {
                continue
            }
            tab.setNoteTitle(title.isEmpty ? String(localized: "Untitled", comment: "Placeholder of a note's empty title") : title)
        }
    }
}
