import Foundation

/// Notes made from the sidebar (task 12.5).
extension TabManager {
    /// A new standalone note of `profileID`, in a pinned tab at the end of the folder `folderID`, selected; a collapsed
    /// folder opens. Nil if no note can be made (private window).
    @discardableResult
    func newNoteTab(inFolder folderID: UUID, store: NoteStore, profileID: UUID?) -> BrowserTab? {
        guard let note = store.createNote(profileID: profileID), let url = NoteTab.url(for: note.id) else {
            return nil
        }
        let tab = newTab(url: url)
        move(tab, to: .pinned(folder: folderID, index: layout.pinned.folder(folderID)?.items.count ?? 0))
        if layout.pinned.folder(folderID)?.isCollapsed == true {
            toggleFolder(folderID)
        }
        return tab
    }
}
