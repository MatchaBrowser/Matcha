import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Notes of a session (task 12.1): making, writing, linking, finding a page's note, private windows.
@MainActor
struct NoteStoreTests {
    private let container: ModelContainer
    private let store: NoteStore
    private let profile = UUID()
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    init() throws {
        container = try BrowserSchema.makeContainer(inMemory: true)
        store = NoteStore(context: container.mainContext)
    }

    private func link(_ address: String, _ scope: NoteLinkScope = .page) throws -> NoteLink {
        let url = try #require(URL(string: address))
        return try #require(NoteLink(url: url, scope: scope, title: "Page"))
    }

    @Test func `a private window has no notes`() throws {
        let privateStore = NoteStore(context: nil)
        #expect(!privateStore.isPersistent)
        #expect(privateStore.createNote(profileID: profile) == nil)
        #expect(try privateStore.note(linkedTo: #require(URL(string: "https://example.com")), profileID: profile) == nil)
        #expect(privateStore.setContent("[]", of: UUID()) == .notFound)
    }

    @Test func `a note is written, its text taken for search, and moves to the top`() throws {
        let first = try #require(store.createNote(profileID: profile, title: "  Trip  ", date: start))
        let second = try #require(store.createNote(profileID: profile, date: start.addingTimeInterval(10)))
        #expect(first.title == "Trip")
        #expect(store.notes.map(\.id) == [second.id, first.id])

        let content = "[{\"type\": \"paragraph\", \"content\": [{\"type\": \"text\", \"text\": \"Book the train\"}]}]"
        #expect(store.setContent(content, of: first.id, date: start.addingTimeInterval(20)) == .saved)
        #expect(store.content(of: first.id) == content)
        #expect(store.record(first.id)?.plainText == "Book the train")
        #expect(store.notes.map(\.id) == [first.id, second.id])
        #expect(store.notes.first?.modifiedAt == start.addingTimeInterval(20))
        #expect(store.setContent(content, of: first.id) == .unchanged)
    }

    @Test func `a document too large is not saved`() throws {
        let note = try #require(store.createNote(profileID: profile))
        let large = "[\"" + String(repeating: "a", count: NoteStore.maximumContentBytes) + "\"]"
        #expect(store.setContent(large, of: note.id) == .tooLarge)
        #expect(store.content(of: note.id) == "[]")
        #expect(store.setContent("[]", of: UUID()) == .notFound)
    }

    @Test func `titles are trimmed and capped`() throws {
        let note = try #require(store.createNote(profileID: profile))
        store.rename(note.id, to: String(repeating: "x", count: NoteStore.maximumTitleLength + 10))
        #expect(store.notes.first?.title.count == NoteStore.maximumTitleLength)
        store.rename(note.id, to: "   ")
        #expect(store.notes.first?.title.isEmpty == true)
    }

    @Test func `the note of a page comes before the note of its site`() throws {
        let page = try #require(URL(string: "https://docs.example.com/guide?utm_source=mail#intro"))
        let siteNote = try #require(store.createNote(profileID: profile, link: link("https://www.example.com/", .site), date: start))
        #expect(store.note(linkedTo: page, profileID: profile)?.id == siteNote.id)

        let pageNote = try #require(store.createNote(
            profileID: profile,
            link: link("https://docs.example.com/guide"),
            date: start.addingTimeInterval(10),
        ))
        #expect(store.note(linkedTo: page, profileID: profile)?.id == pageNote.id)
        // Another profile doesn't see them; another page of the site finds the site's note.
        #expect(store.note(linkedTo: page, profileID: UUID()) == nil)
        #expect(try store.note(linkedTo: #require(URL(string: "https://example.com/other")), profileID: profile)?.id == siteNote.id)

        // Detached, the page's note no longer answers for it.
        store.setLink(nil, of: pageNote.id)
        #expect(store.note(linkedTo: page, profileID: profile)?.id == siteNote.id)
    }

    @Test func `the most recent note of a page answers for it`() throws {
        let page = try link("https://example.com/a")
        _ = store.createNote(profileID: profile, link: page, date: start)
        let recent = try #require(store.createNote(profileID: profile, link: page, date: start.addingTimeInterval(10)))
        #expect(store.note(linkedTo: page.url, profileID: profile)?.id == recent.id)
    }

    @Test func `deleting notes, or all those of a profile`() throws {
        let other = UUID()
        let note = try #require(store.createNote(profileID: profile))
        _ = store.createNote(profileID: profile)
        _ = store.createNote(profileID: other)
        _ = store.createFolder(named: "Work", profileID: profile)
        _ = store.createFolder(named: "Home", profileID: other)

        store.delete(note.id)
        #expect(store.notes(ofProfile: profile).count == 1)
        #expect(store.content(of: note.id) == nil)

        store.removeAll(profileID: profile)
        #expect(store.notes.map(\.profileID) == [other])
        #expect(store.folders.map(\.profileID) == [other])
        #expect(try container.mainContext.fetchCount(FetchDescriptor<NoteRecord>()) == 1)
    }

    @Test func `notes are read back from the store`() throws {
        let folder = try #require(store.createFolder(named: "Work", profileID: profile))
        let note = try #require(store.createNote(
            profileID: profile,
            title: "Plan",
            folderID: folder.id,
            link: link("https://example.com/a"),
        ))
        store.setContent("[{\"type\": \"paragraph\"}]", of: note.id)

        let reopened = NoteStore(context: ModelContext(container))
        let summary = try #require(reopened.notes.first)
        #expect(summary.title == "Plan")
        #expect(summary.folderID == folder.id)
        #expect(summary.link?.key == "example.com/a")
        #expect(reopened.content(of: note.id) == "[{\"type\": \"paragraph\"}]")
        #expect(reopened.folders.map(\.name) == ["Work"])
    }
}
