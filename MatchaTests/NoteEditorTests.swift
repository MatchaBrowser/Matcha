import AppKit
import Foundation
@testable import Matcha
import SwiftData
import Testing
import WebKit

/// The notes editor in a real web view (task 12.2): the app's page, a note shown, typing saved, the previous note saved
/// before the next one, an unreadable note never rewritten, no network, no way out, the bridge out of the page's reach.
@MainActor
@Suite(.webKit)
struct NoteEditorTests {
    private let container: ModelContainer
    private let store: NoteStore
    private let editor: NoteEditor
    /// Never shown: the page needs a window to take the keyboard.
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 600, height: 800),
        styleMask: [.titled],
        backing: .buffered,
        defer: false,
    )

    init() throws {
        container = try BrowserSchema.makeContainer(inMemory: true)
        store = NoteStore(context: container.mainContext)
        editor = NoteEditor(store: store)
        window.contentView = editor.webView
    }

    private func paragraph(_ text: String) -> String {
        let inline = "{\"type\": \"text\", \"text\": \"\(text)\", \"styles\": {}}"
        return "[{\"id\": \"p\", \"type\": \"paragraph\", \"props\": {}, \"content\": [\(inline)]}]"
    }

    private func note(_ text: String) throws -> UUID {
        let note = try #require(store.createNote(profileID: nil))
        store.setContent(paragraph(text), of: note.id)
        return note.id
    }

    private func pageText() async throws -> String {
        try await editor.webView.evaluateJavaScript("document.querySelector('.ProseMirror')?.innerText ?? ''") as? String ?? ""
    }

    private func showing(_ text: String) async throws {
        try await waitUntilAsync { try await pageText().contains(text) }
    }

    /// Types `text` at the end of the note, as the keyboard would, once the editor is there.
    private func type(_ text: String) async throws {
        try await waitUntilAsync {
            try await editor.webView.evaluateJavaScript("document.querySelector('.ProseMirror') !== null") as? Bool == true
        }
        _ = try await editor.webView.callAsyncJavaScript(
            """
            const editor = document.querySelector('.ProseMirror');
            editor.focus();
            const range = document.createRange();
            range.selectNodeContents(editor.lastElementChild ?? editor);
            range.collapse(false);
            getSelection().removeAllRanges();
            getSelection().addRange(range);
            return document.execCommand('insertText', false, text);
            """,
            arguments: ["text": text],
            contentWorld: .page,
        )
    }

    @Test func `a note is shown, and what is typed is saved`() async throws {
        let id = try note("Book the train")
        await editor.open(id)
        try await showing("Book the train")
        #expect(editor.state == .editing)

        try await type(" before Friday")
        try await waitUntil { store.record(id)?.plainText == "Book the train before Friday" }
        #expect(store.content(of: id)?.contains("\"type\":\"paragraph\"") == true)
    }

    @Test func `the note shown is saved before the next one`() async throws {
        let first = try note("First")
        let second = try note("Second")
        await editor.open(first)
        try await showing("First")

        try await type(" changed")
        await editor.open(second)
        #expect(store.record(first)?.plainText == "First changed")
        try await showing("Second")
        #expect(try await !pageText().contains("First"))
    }

    @Test func `an unreadable note is shown read-only and never saved`() async throws {
        let id = try #require(store.createNote(profileID: nil)?.id)
        let content = "[{\"type\": \"futureBlock\", \"content\": [{\"type\": \"text\", \"text\": \"From a newer Matcha\"}]}]"
        store.setContent(content, of: id)
        await editor.open(id)
        try await waitUntil { editor.state == .unreadable }

        try await type("lost")
        await editor.flush()
        #expect(try await !holds(within: .seconds(1)) { store.content(of: id) != content })
        #expect(store.content(of: id) == content)
    }

    @Test func `a deleted note leaves the editor empty`() async throws {
        let id = try note("Gone")
        store.delete(id)
        await editor.open(id)
        #expect(editor.state == .empty)
        #expect(editor.noteID == nil)
    }

    @Test func `the page reaches neither the network nor another page`() async throws {
        try await editor.open(note("Safe"))
        try await showing("Safe")
        let fetched = try await editor.webView.callAsyncJavaScript(
            "return await fetch('https://example.com/').then(() => 'loaded', () => 'blocked');",
            contentWorld: .page,
        ) as? String
        #expect(fetched == "blocked")

        _ = try await editor.webView.evaluateJavaScript("location.href = 'https://example.com/'; true")
        #expect(try await !holds(within: .seconds(1)) { editor.webView.url?.scheme != NoteEditorResources.scheme })
    }

    @Test func `the bridge is out of the page's reach`() async throws {
        try await editor.open(note("Bridge"))
        try await showing("Bridge")
        let inPage = try await editor.webView.evaluateJavaScript(
            "typeof window.webkit?.messageHandlers?.\(NoteEditorScript.handlerName) + ' ' + typeof window.\(NoteEditorScript.bridgeName)",
        ) as? String
        #expect(inPage == "undefined undefined")
        let inWorld = try await editor.webView.callAsyncJavaScript(
            "return typeof window[bridge];",
            arguments: ["bridge": NoteEditorScript.bridgeName],
            contentWorld: NoteEditorScript.world,
        ) as? String
        #expect(inWorld == "object")
    }

    @Test func `a link of the note goes to the browser`() async throws {
        var opened: [URL] = []
        editor.openLink = { opened.append($0) }
        try await editor.open(note("Links"))
        try await showing("Links")
        _ = try await editor.webView
            .evaluateJavaScript("window.open('https://example.com/a', '_blank'); window.open('file:///etc/hosts'); true")
        try await waitUntil { opened == [URL(string: "https://example.com/a")] }
    }
}
