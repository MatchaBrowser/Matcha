import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Notes panel of a window (task 12.3): the note of the page shown, made for the page or its site, its scope, detached
/// or deleted, the panel kept open or not from one tab to the next, none in a private window.
@MainActor
@Suite(.webKit)
struct NotesPanelModelTests {
    private let container: ModelContainer
    private let store: NoteStore
    private let panel: NotesPanelModel
    private let profile = UUID()

    init() throws {
        container = try BrowserSchema.makeContainer(inMemory: true)
        store = NoteStore(context: container.mainContext)
        panel = NotesPanelModel(store: store)
        let profile = profile
        panel.profileID = { profile }
    }

    private func url(_ address: String) throws -> URL {
        try #require(URL(string: address))
    }

    @Test func `a private window has no notes panel`() {
        let privatePanel = NotesPanelModel(store: NoteStore(context: nil))
        #expect(!privatePanel.isAvailable)
        privatePanel.open()
        #expect(!privatePanel.isOpen)
        #expect(privatePanel.editor == nil)
    }

    @Test func `a note is made for the page shown, titled like it, and opened`() async throws {
        panel.open()
        try panel.show(page: url("https://docs.example.com/guide?utm_source=mail#intro"), title: "Guide")
        #expect(panel.note == nil)
        #expect(panel.canLink)
        #expect(panel.site == "example.com")

        panel.createNote(scope: .page)
        let note = try #require(panel.note)
        #expect(note.title == "Guide")
        #expect(note.link?.key == "docs.example.com/guide")
        #expect(note.profileID == profile)
        let editor = try #require(panel.editor)
        try await waitUntil { editor.noteID == note.id }
    }

    @Test func `a site's note shows on its other pages, the page's own first`() throws {
        try panel.show(page: url("https://example.com/a"), title: "A")
        panel.createNote(scope: .site)
        let siteNote = try #require(panel.note)

        try panel.show(page: url("https://www.example.com/b"), title: "B")
        #expect(panel.note?.id == siteNote.id)
        panel.createNote(scope: .page)
        #expect(panel.note?.id != siteNote.id)
        #expect(panel.note?.link?.scope == .page)

        // Another profile doesn't see them.
        let other = UUID()
        panel.profileID = { other }
        #expect(panel.note == nil)
    }

    @Test func `the scope of the note changes`() throws {
        try panel.show(page: url("https://example.com/a"), title: "A")
        panel.createNote(scope: .page)
        panel.setScope(.site)
        #expect(panel.note?.link?.scope == .site)
        try panel.show(page: url("https://example.com/other"), title: nil)
        #expect(panel.note != nil)
    }

    @Test func `a detached note leaves the page, a deleted one is gone`() throws {
        try panel.show(page: url("https://example.com/a"), title: "A")
        panel.createNote(scope: .page)
        let id = try #require(panel.note?.id)
        panel.detachNote()
        #expect(panel.note == nil)
        #expect(store.notes.first?.id == id)
        #expect(store.notes.first?.link == nil)

        panel.createNote(scope: .page)
        panel.deleteNote()
        #expect(panel.note == nil)
        #expect(store.notes.map(\.id) == [id])
    }

    @Test func `no note outside the web`() throws {
        try panel.show(page: url("about:blank"), title: nil)
        #expect(!panel.canLink)
        panel.createNote(scope: .page)
        #expect(store.notes.isEmpty)
        panel.show(page: nil, title: nil)
        #expect(!panel.canLink)
    }

    @Test func `the panel closes with another tab unless the settings keep it open`() {
        panel.open()
        panel.selectedTabDidChange(keepsOpen: true)
        #expect(panel.isOpen)
        panel.selectedTabDidChange(keepsOpen: false)
        #expect(!panel.isOpen)
        #expect(panel.editor == nil)

        panel.toggle()
        #expect(panel.isOpen)
        #expect(panel.editor != nil)
        panel.toggle()
        #expect(!panel.isOpen)
    }
}
