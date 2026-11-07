import Foundation
import Observation

/// The notes library window (task 12.4): the notes of the profile shown by the main window, by section (all, page
/// notes and their sites, folders), the search, and the note chosen in its editor. Its editor is made when the window
/// opens (`start`) and freed when it closes (`stop`), once the note is saved.
@MainActor
@Observable
final class NotesLibraryModel {
    let store: NoteStore
    /// Profile shown: that of the Space of the main window (`MiniWindowManager.historyProfile`).
    var profileID: UUID? {
        didSet {
            if profileID != oldValue {
                section = .all
                select(nil)
            }
        }
    }

    var section: NotesLibrarySection? = .all
    private(set) var selectedNoteID: UUID?
    var searchText = ""
    private(set) var editor: NoteEditor?
    @ObservationIgnored private let makeEditor: @MainActor (NoteStore) -> NoteEditor

    init(store: NoteStore, profileID: UUID?, makeEditor: @escaping @MainActor (NoteStore) -> NoteEditor = { NoteEditor(store: $0) }) {
        self.store = store
        self.profileID = profileID
        self.makeEditor = makeEditor
    }

    /// Notes of the section chosen, filtered by the search, the most recently changed first.
    var notes: [NoteSummary] {
        let shown = (section ?? .all).notes(in: store.notes(ofProfile: profileID))
        guard let matches = store.search(searchText, profileID: profileID) else {
            return shown
        }
        return shown.filter { matches.contains($0.id) }
    }

    var sites: [String] {
        NotesLibrarySection.sites(in: store.notes(ofProfile: profileID))
    }

    var selectedNote: NoteSummary? {
        selectedNoteID.flatMap { id in store.notes.first { $0.id == id } }
    }

    func folders(in parentID: UUID?) -> [NoteFolder] {
        store.folders(ofProfile: profileID, parentID: parentID)
    }

    /// Folder chosen in the sidebar, where a new note or folder goes.
    var selectedFolderID: UUID? {
        if case let .folder(id) = section {
            return id
        }
        return nil
    }

    func start() {
        if editor == nil {
            editor = makeEditor(store)
        }
        showSelection()
    }

    /// The window closes: the note shown is saved, then the editor freed.
    func stop() {
        let editor = editor
        self.editor = nil
        Task { await editor?.flush() }
    }

    /// Shows the note `id` in the editor (nil: none).
    func select(_ id: UUID?) {
        selectedNoteID = id
        showSelection()
    }

    /// A new note in the folder chosen (otherwise at the root), chosen at once.
    func newNote() {
        guard let note = store.createNote(profileID: profileID, folderID: selectedFolderID) else {
            return
        }
        if case .pageNotes = section ?? .all {
            section = .all
        } else if case .site = section ?? .all {
            section = .all
        }
        select(note.id)
    }

    @discardableResult
    func newFolder(named name: String) -> NoteFolder? {
        store.createFolder(named: name, parentID: selectedFolderID, profileID: profileID)
    }

    func delete(_ ids: Set<UUID>) {
        ids.forEach(store.delete)
        if let selectedNoteID, ids.contains(selectedNoteID) {
            select(nil)
        }
    }

    /// Deletes a folder, its subfolders and their notes; the sidebar goes back to all the notes if it showed it.
    func deleteFolder(_ id: UUID) {
        store.deleteFolder(id)
        if case let .folder(shown) = section, !store.folders.contains(where: { $0.id == shown }) {
            section = .all
        }
        if let selectedNoteID, !store.notes.contains(where: { $0.id == selectedNoteID }) {
            select(nil)
        }
    }

    /// The editor follows the note chosen, also when it is deleted elsewhere (the view calls it when the list changes).
    func showSelection() {
        if let id = selectedNoteID, !store.notes.contains(where: { $0.id == id }) {
            selectedNoteID = nil
        }
        guard let editor, editor.noteID != selectedNoteID else {
            return
        }
        let id = selectedNoteID
        Task { await editor.open(id) }
    }
}
