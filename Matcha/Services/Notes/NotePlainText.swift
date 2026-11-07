import Foundation

/// Text of a note, for search (task 12.1): the text of each block of its document (OpenBlock's JSON, `SYNC.md` § 2.10),
/// one line per block, in order, the children after their block. A link gives its text, a line break a new line; the
/// other inline content and the properties (captions, addresses) are left out. Pure type.
nonisolated enum NotePlainText {
    /// Blocks nested deeper are left out: a received document can't exhaust the stack.
    static let maximumDepth = 32
    /// Longest text kept, in characters.
    static let maximumLength = 200_000

    /// Text of `content`; nil if it is not an array of blocks.
    static func text(of content: String) -> String? {
        guard let blocks = (try? JSONSerialization.jsonObject(with: Data(content.utf8))) as? [Any] else {
            return nil
        }
        var lines: [String] = []
        var length = 0
        collect(blocks, depth: 0, into: &lines, length: &length)
        return String(lines.joined(separator: "\n").prefix(maximumLength))
    }

    private static func collect(_ blocks: [Any], depth: Int, into lines: inout [String], length: inout Int) {
        for case let block as [String: Any] in blocks {
            guard length < maximumLength else {
                return
            }
            let line = inlineText(block["content"])
            if !line.isEmpty {
                lines.append(line)
                length += line.count + 1
            }
            if depth < maximumDepth, let children = block["children"] as? [Any] {
                collect(children, depth: depth + 1, into: &lines, length: &length)
            }
        }
    }

    /// Text of a block's inline content: texts, the texts of links (one level), line breaks.
    private static func inlineText(_ content: Any?, inLink: Bool = false) -> String {
        guard let items = content as? [Any] else {
            return ""
        }
        var text = ""
        for case let item as [String: Any] in items {
            switch item["type"] as? String {
            case "text": text += item["text"] as? String ?? ""
            case "link" where !inLink: text += inlineText(item["content"], inLink: true)
            case "hardBreak": text += "\n"
            default: break
            }
        }
        return text
    }
}
