import Foundation
@testable import Matcha
import Testing

/// What the notes editor's page may send and get (task 12.2): messages read with caps, files served, texts of the menus.
struct NoteEditorProtocolTests {
    // MARK: Messages

    @Test func `messages of the bridge are read`() {
        #expect(NoteEditorMessage(body: ["type": "ready"]) == .ready)
        #expect(NoteEditorMessage(body: ["type": "change", "token": "t", "content": "[]"]) == .change(token: "t", content: "[]"))
        #expect(NoteEditorMessage(body: ["type": "unreadable", "token": "t"]) == .unreadable(token: "t"))
    }

    @Test func `malformed messages are refused`() {
        #expect(NoteEditorMessage(body: nil) == nil)
        #expect(NoteEditorMessage(body: "ready") == nil)
        #expect(NoteEditorMessage(body: ["type": "save", "token": "t"]) == nil)
        #expect(NoteEditorMessage(body: ["type": "change", "content": "[]"]) == nil)
        #expect(NoteEditorMessage(body: ["type": "change", "token": "t", "content": 3]) == nil)
        #expect(NoteEditorMessage(body: ["type": "change", "token": "", "content": "[]"]) == nil)
        let longToken = String(repeating: "t", count: NoteEditorMessage.maximumTokenLength + 1)
        #expect(NoteEditorMessage(body: ["type": "unreadable", "token": longToken]) == nil)
    }

    @Test func `a document too large is not taken`() {
        let message = NoteEditorMessage(body: ["type": "change", "token": "t", "content": "[\"12345\"]"], maximumContentBytes: 5)
        #expect(message == .tooLarge(token: "t"))
    }

    @Test func `the page gets its note as JSON`() throws {
        let payload = NoteEditorPayload(token: "t", content: "[{\"type\":\"paragraph\"}]", editable: true, texts: ["placeholder": "Écrire"])
        let json = try #require(payload.json)
        let object = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        #expect(object["content"] as? String == "[{\"type\":\"paragraph\"}]")
        #expect(object["editable"] as? Bool == true)
        #expect((object["texts"] as? [String: String])?["placeholder"] == "Écrire")
    }

    // MARK: Files

    @Test func `only the editor's files are served`() throws {
        let page = try #require(URL(string: NoteEditorResources.pageAddress))
        #expect(NoteEditorResources.file(for: page)?.mimeType == "text/html")
        #expect(NoteEditorResources.isPage(page))
        #expect(try NoteEditorResources.file(for: #require(URL(string: "matcha-note://editor/note-editor.js")))?
            .mimeType == "text/javascript")
        let refused = [
            "matcha-note://editor/other.js", "matcha-note://other/note-editor.js", "https://editor/note-editor.js",
            "matcha-note://editor/note-editor.html?x=1", "matcha-note://editor/../note-editor.js",
        ]
        for address in refused {
            #expect(try NoteEditorResources.file(for: #require(URL(string: address))) == nil, "\(address)")
        }
        #expect(try !NoteEditorResources.isPage(#require(URL(string: "matcha-note://editor/note-editor.css"))))
    }

    @Test func `the files are in the app, with the same policy in the page and its header`() throws {
        for file in NoteEditorResources.files.values {
            #expect(NoteEditorResources.data(of: file, in: .main) != nil, "\(file.name)")
        }
        let page = try #require(NoteEditorResources.files["/note-editor.html"])
        let html = try #require(NoteEditorResources.data(of: page, in: .main).flatMap { String(data: $0, encoding: .utf8) })
        #expect(html.contains("content=\"\(NoteEditorResources.contentSecurityPolicy)\""))
        let headers = NoteEditorResources.headers(for: page)
        #expect(headers["Content-Security-Policy"] == NoteEditorResources.contentSecurityPolicy)
        #expect(headers["Content-Type"] == "text/html; charset=utf-8")
    }

    // MARK: Texts

    @Test func `every replaceable text of the menus is given`() {
        let texts = NoteEditorTexts.current
        let slashItems = [
            "heading1", "heading2", "heading3", "bulletList", "orderedList", "checklist", "quote", "calloutInfo", "calloutWarning",
            "calloutSuccess", "calloutError", "codeBlock", "divider", "columns2", "columns3", "columnsSidebar", "table", "table2x2",
            "table4x4",
        ]
        for item in slashItems {
            #expect(texts["slash.\(item).title"]?.isEmpty == false, "\(item)")
            #expect(texts["slash.\(item).description"]?.isEmpty == false, "\(item)")
        }
        for group in ["Basic blocks", "Lists", "Layout"] {
            #expect(texts["slash.group.\(group)"]?.isEmpty == false, "\(group)")
        }
        for item in ["bold", "italic", "underline", "strikethrough", "code", "alignLeft", "alignCenter", "alignRight"] {
            #expect(texts["bubble.\(item)"]?.isEmpty == false, "\(item)")
        }
        #expect(texts["placeholder"]?.isEmpty == false)
        #expect(texts.count == slashItems.count * 2 + 3 + 8 + 1)
    }
}
