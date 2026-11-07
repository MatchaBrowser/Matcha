import Foundation
@testable import Matcha
import Testing

/// Export of the notes as Markdown (task 12.9): blocks and styles converted, colors left out, and the files of
/// “Export All Notes…” in folders like the library's.
struct NoteMarkdownTests {
    private func text(_ value: String, _ styles: String = "{}") -> String {
        "{\"type\": \"text\", \"text\": \"\(value)\", \"styles\": \(styles)}"
    }

    private var document: String {
        let blocks = [
            #"{"type": "heading", "props": {"level": 1}, "content": [\#(text("Trip"))]}"#,
            #"{"type": "paragraph", "content": [\#(text("Book ")), \#(text("now", #"{"bold": true, "textColor": "red"}"#)), "#
                + #"\#(text(" or ")), \#(text("later", #"{"italic": true}"#)), {"type": "hardBreak"}, "#
                + #"{"type": "link", "href": "https://example.com", "content": [\#(text("site"))]}, \#(text(" *x*"))]}"#,
            #"{"type": "bulletList", "children": [{"type": "listItem", "content": [\#(text("One"))], "children": ["#
                + #"{"type": "orderedList", "children": [{"type": "listItem", "content": [\#(text("Sub"))]}]}]}]}"#,
            #"{"type": "checkList", "children": [{"type": "checkListItem", "props": {"checked": true}, "content": [\#(text("Done"))]}, "#
                + #"{"type": "checkListItem", "props": {"checked": false}, "content": [\#(text("Todo"))]}]}"#,
            #"{"type": "blockquote", "content": [\#(text("Quoted"))]}"#,
            #"{"type": "codeBlock", "props": {"language": "swift"}, "content": [\#(text("let a = 1"))]}"#,
            #"{"type": "divider"}"#,
            #"{"type": "table", "children": [{"type": "tableRow", "children": [{"type": "tableHeader", "content": [\#(text("A"))]}, "#
                + #"{"type": "tableHeader", "content": [\#(text("B|C"))]}]}, {"type": "tableRow", "children": ["#
                + #"{"type": "tableCell", "content": [\#(text("1"))]}, {"type": "tableCell", "content": [\#(text("2"))]}]}]}"#,
        ]
        return "[" + blocks.joined(separator: ", ") + "]"
    }

    @Test func `blocks and styles become Markdown`() throws {
        let link = try NoteLink(url: #require(URL(string: "https://example.com/page")), scope: .page, title: "Page")
        let markdown = try #require(NoteMarkdown.markdown(title: "My Note", content: document, link: link))
        let expected = [
            "# My Note", "", "[Page](https://example.com/page)", "", "## Trip", "",
            "Book **now** or _later_  ", "[site](https://example.com) \\*x\\*", "",
            "- One", "  1. Sub", "", "- [x] Done", "- [ ] Todo", "", "> Quoted", "", "```swift", "let a = 1", "```", "", "---", "",
            "| A | B\\|C |", "| --- | --- |", "| 1 | 2 |", "",
        ]
        #expect(markdown == expected.joined(separator: "\n"))
    }

    @Test func `a document that isn't blocks has no Markdown`() {
        #expect(NoteMarkdown.markdown(title: "T", content: "{}", link: nil) == nil)
        #expect(NoteMarkdown.markdown(title: "", content: "[]", link: nil) == "\n")
    }

    @Test func `all the notes go to folders like the library's`() throws {
        let work = NoteFolder(id: UUID(), name: "Work", order: 0, profileID: nil, parentID: nil)
        let client = NoteFolder(id: UUID(), name: "Client: A/B", order: 0, profileID: nil, parentID: work.id)
        let link = try NoteLink(url: #require(URL(string: "https://docs.apple.com/a")), scope: .page, title: nil)
        func note(_ title: String, folder: UUID? = nil, link: NoteLink? = nil) -> NoteSummary {
            NoteSummary(id: UUID(), title: title, profileID: nil, folderID: folder, link: link, createdAt: .now, modifiedAt: .now)
        }
        let documents = [
            (note: note("Plan", folder: client.id), content: "[]"),
            (note: note("Plan", folder: client.id), content: "[]"),
            (note: note("", folder: nil), content: "[]"),
            (note: note("Page", folder: work.id, link: link), content: "[]"),
            (note: note("Broken"), content: "{}"),
        ]
        let files = NoteExportPlan.files(for: documents, folders: [work, client], pageNotesName: "Page Notes")
        #expect(files.map { $0.path.joined(separator: "/") } == [
            "Work/Client- A-B/Plan.md", "Work/Client- A-B/Plan 2.md", "Untitled.md", "Page Notes/apple.com/Page.md",
        ])
        #expect(NoteExportPlan.safeName("  ..hidden  ") == "hidden")
    }
}
