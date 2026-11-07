import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Notes library (task 12.4): sections (all, page notes by site, folders), search in titles and texts, a new note in
/// the folder chosen, a deleted note or folder leaving the editor, the profile shown.
@MainActor
@Suite(.webKit)
struct NotesLibraryModelTests {
    private let container: ModelContainer
    private let store: NoteStore
    private let library: NotesLibraryModel
    private let profile = UUID()

    init() throws {
        container = try BrowserSchema.makeContainer(inMemory: true)
        store = NoteStore(context: container.mainContext)
        library = NotesLibraryModel(store: store, profileID: profile)
    }

    private func link(_ address: String, _ scope: NoteLinkScope = .page) throws -> NoteLink {
        let url = try #require(URL(string: address))
        return try #require(NoteLink(url: url, scope: scope, title: nil))
    }

    @Test func `notes are listed by section`() throws {
        let folder = try #require(store.createFolder(named: "Work", profileID: profile))
        let loose = try #require(store.createNote(profileID: profile, title: "Loose"))
        let filed = try #require(store.createNote(profileID: profile, title: "Filed", folderID: folder.id))
        let page = try #require(store.createNote(
            profileID: profile,
            title: "Page",
            folderID: folder.id,
            link: link("https://docs.apple.com/a"),
        ))
        let site = try #require(store.createNote(profileID: profile, title: "Site", link: link("https://example.org/", .site)))
        _ = store.createNote(profileID: UUID(), title: "Other profile")

        #expect(Set(library.notes.map(\.id)) == [loose.id, filed.id, page.id, site.id])
        library.section = .pageNotes
        #expect(Set(library.notes.map(\.id)) == [page.id, site.id])
        #expect(library.sites == ["apple.com", "example.org"])
        library.section = .site("apple.com")
        #expect(library.notes.map(\.id) == [page.id])
        // A linked note shows under the page notes, whatever its folder.
        library.section = .folder(folder.id)
        #expect(library.notes.map(\.id) == [filed.id])
    }

    @Test func `the search looks in titles and texts, whatever the case and the accents`() throws {
        let trip = try #require(store.createNote(profileID: profile, title: "Voyage à Lyon"))
        let recipe = try #require(store.createNote(profileID: profile, title: "Recette"))
        store.setContent("[{\"type\": \"paragraph\", \"content\": [{\"type\": \"text\", \"text\": \"Crème brûlée\"}]}]", of: recipe.id)
        _ = store.createNote(profileID: UUID(), title: "Voyage ailleurs")

        library.searchText = "voyage a"
        #expect(library.notes.map(\.id) == [trip.id])
        library.searchText = "CREME"
        #expect(library.notes.map(\.id) == [recipe.id])
        library.searchText = "  "
        #expect(library.notes.count == 2)
        #expect(store.search("lyon", profileID: UUID()) == [])
        #expect(NoteStore(context: nil).search("lyon", profileID: profile) == [])
    }

    @Test func `a new note goes to the folder chosen and is shown`() async throws {
        library.start()
        let folder = try #require(library.newFolder(named: "Ideas"))
        library.section = .folder(folder.id)
        library.newNote()
        let note = try #require(library.selectedNote)
        #expect(note.folderID == folder.id)
        #expect(note.profileID == profile)
        let editor = try #require(library.editor)
        try await waitUntil { editor.noteID == note.id }

        // From the page notes, a new note is standalone: the list goes back to all the notes.
        library.section = .pageNotes
        library.newNote()
        #expect(library.section == .all)
        #expect(library.selectedNote?.folderID == nil)
        library.stop()
        #expect(library.editor == nil)
    }

    @Test func `a deleted note or folder leaves the selection`() throws {
        let folder = try #require(store.createFolder(named: "Old", profileID: profile))
        let note = try #require(store.createNote(profileID: profile, folderID: folder.id))
        library.section = .folder(folder.id)
        library.select(note.id)
        library.deleteFolder(folder.id)
        #expect(library.section == .all)
        #expect(library.selectedNoteID == nil)

        let other = try #require(store.createNote(profileID: profile))
        library.select(other.id)
        library.delete([other.id])
        #expect(library.selectedNoteID == nil)
        #expect(store.notes.isEmpty)
    }

    @Test func `another profile starts from all its notes`() throws {
        let note = try #require(store.createNote(profileID: profile))
        library.section = .pageNotes
        library.select(note.id)
        library.profileID = UUID()
        #expect(library.section == .all)
        #expect(library.selectedNoteID == nil)
        #expect(library.notes.isEmpty)
    }
}
