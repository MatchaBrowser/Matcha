import Foundation
@testable import Matcha
import Testing

/// Text of a note's document, for search (task 12.1): OpenBlock's blocks as JSON.
struct NotePlainTextTests {
    @Test func `each block gives a line, children after their block`() {
        let content = """
        [
            {"id": "1", "type": "heading", "props": {"level": 1}, "content": [{"type": "text", "text": "Trip", "styles": {}}]},
            {"id": "2", "type": "paragraph", "props": {}, "content": [
                {"type": "text", "text": "Book the ", "styles": {}},
                {"type": "text", "text": "train", "styles": {"bold": true, "textColor": "red"}},
                {"type": "text", "text": " on ", "styles": {}},
                {"type": "link", "href": "https://example.com", "content": [{"type": "text", "text": "the site", "styles": {}}]},
                {"type": "hardBreak"},
                {"type": "text", "text": "before Friday", "styles": {}}
            ]},
            {"id": "3", "type": "bulletList", "props": {}, "children": [
                {"id": "4", "type": "listItem", "props": {}, "content": [{"type": "text", "text": "Tickets", "styles": {}}]},
                {"id": "5", "type": "listItem", "props": {}, "content": [{"type": "text", "text": "Hotel", "styles": {}}]}
            ]},
            {"id": "6", "type": "divider", "props": {}},
            {"id": "7", "type": "image", "props": {"src": "https://example.com/a.png", "caption": "Left out"}}
        ]
        """
        #expect(NotePlainText.text(of: content) == "Trip\nBook the train on the site\nbefore Friday\nTickets\nHotel")
    }

    @Test func `an empty document has no text, something else none at all`() {
        #expect(NotePlainText.text(of: "[]")?.isEmpty == true)
        #expect(NotePlainText.text(of: "") == nil)
        #expect(NotePlainText.text(of: "{\"type\": \"paragraph\"}") == nil)
        #expect(NotePlainText.text(of: "[1, \"two\", {\"content\": 3}]")?.isEmpty == true)
    }

    @Test func `blocks nested too deep are left out`() {
        var block = "{\"type\": \"paragraph\", \"content\": [{\"type\": \"text\", \"text\": \"deepest\"}]}"
        for _ in 0 ..< 40 {
            block = "{\"type\": \"bulletList\", \"content\": [{\"type\": \"text\", \"text\": \"level\"}], \"children\": [\(block)]}"
        }
        let text = NotePlainText.text(of: "[\(block)]")
        #expect(text?.split(separator: "\n").count == NotePlainText.maximumDepth + 1)
        #expect(text?.contains("deepest") == false)
    }

    @Test func `the text is capped`() {
        let long = String(repeating: "a", count: NotePlainText.maximumLength + 500)
        let content = "[{\"type\": \"paragraph\", \"content\": [{\"type\": \"text\", \"text\": \"\(long)\"}]}," +
            "{\"type\": \"paragraph\", \"content\": [{\"type\": \"text\", \"text\": \"after\"}]}]"
        #expect(NotePlainText.text(of: content)?.count == NotePlainText.maximumLength)
    }
}
