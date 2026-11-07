import Foundation
@testable import Matcha
import SwiftData
import Testing
import WebKit

/// Notes in tabs (task 12.5): their address, restored at launch, never a web view, a tab leaving its note for a page,
/// and the title following the note.
@MainActor
@Suite(.webKit)
struct NoteTabTests {
    @Test func `a note has an address of its own, the editor's page has none`() throws {
        let id = UUID()
        let url = try #require(NoteTab.url(for: id))
        #expect(url.absoluteString == "matcha-note://note/\(id.uuidString.lowercased())")
        #expect(NoteTab.noteID(in: url) == id)
        #expect(try NoteTab.noteID(in: #require(URL(string: NoteEditorResources.pageAddress))) == nil)
        #expect(try NoteTab.noteID(in: #require(URL(string: "matcha-note://note/not-an-id"))) == nil)
        #expect(try NoteTab.noteID(in: #require(URL(string: "https://note/\(id.uuidString)"))) == nil)
        #expect(NoteEditorResources.file(for: url) == nil)
    }

    @Test func `a note tab comes back at launch, the editor's page doesn't`() throws {
        let note = try #require(NoteTab.url(for: UUID()))
        #expect(StoredTab.restorable(note) == note)
        #expect(try StoredTab.restorable(#require(URL(string: NoteEditorResources.pageAddress))) == nil)
    }

    @Test func `a note tab has no web view, and becomes a page again`() throws {
        let tab = BrowserTab(configuration: WebConfigurationFactory().makeConfiguration(websiteDataStore: .nonPersistent()))
        let id = UUID()
        try tab.load(#require(NoteTab.url(for: id)))
        #expect(tab.noteID == id)
        #expect(tab.webView == nil)
        #expect(!tab.canGoBack)
        tab.loadIfNeeded()
        #expect(tab.webView == nil)
        tab.reload()
        #expect(tab.webView == nil)
        tab.setNoteTitle("Plan")
        #expect(tab.title == "Plan")

        try tab.load(#require(URL(string: "about:blank")))
        #expect(tab.noteID == nil)
        #expect(tab.webView != nil)
        // A page's title is its own.
        tab.setNoteTitle("Other")
        #expect(tab.title != "Other")
        tab.discard()
    }

    @Test func `a note opened in a tab shows its title, also after a rename`() async throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let space = try #require(session.spaces.first)
        let note = try #require(session.notes.createNote(profileID: space.record.profile?.id, title: "Trip"))
        let tab = space.tabManager.newTab(url: NoteTab.url(for: note.id))
        #expect(tab.webView == nil)
        try await waitUntil { tab.title == "Trip" }

        session.notes.rename(note.id, to: "Holidays")
        try await waitUntil { tab.title == "Holidays" }
        session.notes.rename(note.id, to: "")
        try await waitUntil { tab.title == String(localized: "Untitled") }
    }

    @Test func `a new note from a sidebar folder opens in a pinned tab of that folder`() throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let tabManager = try #require(session.spaces.first).tabManager
        let folder = tabManager.newFolder()
        tabManager.toggleFolder(folder)
        let profile = session.spaces.first?.record.profile?.id

        let tab = try #require(tabManager.newNoteTab(inFolder: folder, store: session.notes, profileID: profile))
        let note = try #require(session.notes.notes.first)
        #expect(tab.noteID == note.id)
        #expect(note.profileID == profile)
        #expect(tabManager.layout.pinned.folder(folder)?.items == [.tab(tab.id)])
        #expect(tabManager.layout.pinned.folder(folder)?.isCollapsed == false)
        #expect(tabManager.selectedTab?.id == tab.id)
        #expect(tabManager.newNoteTab(inFolder: folder, store: NoteStore(context: nil), profileID: profile) == nil)
    }
}
