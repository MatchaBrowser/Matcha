import Foundation

/// A passage of a page added to its note (task 12.6, “Add to Note”): a quote block, then a line with a link back to the
/// passage (a text fragment, `#:~:text=`, which scrolls to it and highlights it). Pure type.
nonisolated enum NoteQuote {
    /// Longest passage kept, in characters.
    static let maximumLength = 5000
    /// A longer passage is found by its first and last words (`textStart,textEnd`).
    static let maximumFragmentLength = 300
    static let fragmentWordCount = 4

    /// The passage as it will be quoted: lines kept, spaces of each line gathered, empty lines removed, capped.
    static func cleaned(_ selection: String) -> String {
        let lines = selection.components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
        return String(lines.joined(separator: "\n").prefix(maximumLength))
    }

    /// Address of the passage in `page`: the page without its own fragment, with a text fragment; nil for an empty
    /// passage or an address that can't carry one.
    static func fragmentURL(for passage: String, in page: URL) -> URL? {
        let words = passage.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty, var components = URLComponents(url: page, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let text = words.joined(separator: " ")
        let directive = if text.count <= maximumFragmentLength {
            encoded(text)
        } else {
            encoded(words.prefix(fragmentWordCount).joined(separator: " ")) + ","
                + encoded(words.suffix(fragmentWordCount).joined(separator: " "))
        }
        components.fragment = nil
        guard let address = components.url?.absoluteString else {
            return nil
        }
        return URL(string: address + "#:~:text=" + directive)
    }

    /// `content` (OpenBlock's blocks as JSON) with the quote of `passage` and the link to it at the end; nil if
    /// `content` isn't an array of blocks (a document this version can't read is never rewritten).
    static func appending(_ passage: String, source: URL?, sourceTitle: String, to content: String) -> String? {
        guard var blocks = (try? JSONSerialization.jsonObject(with: Data(content.utf8))) as? [Any] else {
            return nil
        }
        let quote = cleaned(passage)
        guard !quote.isEmpty else {
            return nil
        }
        var inline: [[String: Any]] = []
        for (index, line) in quote.components(separatedBy: "\n").enumerated() {
            if index > 0 {
                inline.append(["type": "hardBreak"])
            }
            inline.append(text(line))
        }
        blocks.append(block("blockquote", content: inline))
        if let source {
            let link: [String: Any] = ["type": "link", "href": source.absoluteString, "content": [text(sourceTitle)]]
            blocks.append(block("paragraph", content: [link]))
        }
        guard let data = try? JSONSerialization.data(withJSONObject: blocks, options: [.withoutEscapingSlashes]) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func block(_ type: String, content: [[String: Any]]) -> [String: Any] {
        ["id": UUID().uuidString.lowercased(), "type": type, "props": [String: Any](), "content": content]
    }

    private static func text(_ value: String) -> [String: Any] {
        ["type": "text", "text": value, "styles": [String: Any]()]
    }

    /// Text of a fragment directive: `-`, `&` and `,` have a meaning there and are always encoded.
    private static func encoded(_ text: String) -> String {
        var allowed = CharacterSet.urlFragmentAllowed
        allowed.remove(charactersIn: "-&,#")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }
}
