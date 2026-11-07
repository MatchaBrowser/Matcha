import Foundation

/// A note as Markdown (task 12.9): its title, the page it is linked to, then its blocks (OpenBlock's JSON): headings,
/// lists, to-do lists, quotes and callouts, code, dividers, tables, columns one after the other; bold, italic,
/// strikethrough, code and links in the text. Colors and underlining have no Markdown: they are left out. Pure type.
nonisolated enum NoteMarkdown {
    static let maximumDepth = 32

    /// Markdown of the note; nil if `content` isn't an array of blocks.
    static func markdown(title: String, content: String, link: NoteLink?) -> String? {
        guard let blocks = (try? JSONSerialization.jsonObject(with: Data(content.utf8))) as? [Any] else {
            return nil
        }
        var parts: [String] = []
        if !title.isEmpty {
            parts.append("# " + escaped(title))
        }
        if let link {
            parts.append("[\(escaped(link.title ?? link.url.absoluteString))](\(link.url.absoluteString))")
        }
        parts += blocks.compactMap { $0 as? [String: Any] }.map { render($0, depth: 0) }.filter { !$0.isEmpty }
        return parts.joined(separator: "\n\n") + "\n"
    }

    private static func render(_ block: [String: Any], depth: Int) -> String {
        guard depth < maximumDepth else {
            return ""
        }
        let props = block["props"] as? [String: Any] ?? [:]
        let children = (block["children"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
        let text = inline(block["content"])
        switch block["type"] as? String {
        case "heading":
            // The note's title is the only “#”: its headings come one level below.
            let level = min(max(props["level"] as? Int ?? 1, 1), 5)
            return String(repeating: "#", count: level + 1) + " " + text
        case "bulletList", "orderedList", "checkList":
            return list(children, ordered: block["type"] as? String == "orderedList", depth: depth)
        case "blockquote", "callout":
            return quoted(([text] + children.map { render($0, depth: depth + 1) }).filter { !$0.isEmpty }.joined(separator: "\n\n"))
        case "codeBlock":
            let language = props["language"] as? String ?? ""
            return "```\(language)\n\(plain(block["content"]))\n```"
        case "divider":
            return "---"
        case "table":
            return table(children)
        case "image":
            return "![\(escaped(props["alt"] as? String ?? ""))](\(props["src"] as? String ?? ""))"
        case "embed":
            let url = props["url"] as? String ?? ""
            return "[\(escaped(url))](\(url))"
        default:
            return ([text] + children.map { render($0, depth: depth + 1) }).filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
    }

    /// Items of a list, nested lists indented by two spaces.
    private static func list(_ items: [[String: Any]], ordered: Bool, depth: Int) -> String {
        items.enumerated().map { index, item in
            let props = item["props"] as? [String: Any] ?? [:]
            let marker = if item["type"] as? String == "checkListItem" {
                props["checked"] as? Bool == true ? "- [x]" : "- [ ]"
            } else {
                ordered ? "\(index + 1)." : "-"
            }
            let nested = (item["children"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }
                .map { render($0, depth: depth + 1) }
                .filter { !$0.isEmpty }
                .map { $0.split(separator: "\n", omittingEmptySubsequences: false).map { "  " + $0 }.joined(separator: "\n") }
            return ([marker + " " + inline(item["content"])] + nested).joined(separator: "\n")
        }
        .joined(separator: "\n")
    }

    /// A table: its first row as the header.
    private static func table(_ rows: [[String: Any]]) -> String {
        let cells = rows.map { row in
            (row["children"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map { cell in
                let own = inline(cell["content"], lineBreak: "<br>")
                let nested = (cell["children"] as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map { inline(
                    $0["content"],
                    lineBreak: "<br>",
                ) }
                return ([own] + nested).filter { !$0.isEmpty }.joined(separator: "<br>").replacingOccurrences(of: "|", with: "\\|")
            }
        }
        guard let header = cells.first, !header.isEmpty else {
            return ""
        }
        let line = { (row: [String]) in "| " + row.joined(separator: " | ") + " |" }
        let separator = "| " + header.map { _ in "---" }.joined(separator: " | ") + " |"
        return ([line(header), separator] + cells.dropFirst().map(line)).joined(separator: "\n")
    }

    private static func quoted(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? ">" : "> " + $0 }.joined(separator: "\n")
    }

    /// Inline content with its styles; a line break ends a Markdown line.
    private static func inline(_ content: Any?, lineBreak: String = "  \n") -> String {
        guard let items = content as? [Any] else {
            return ""
        }
        return items.compactMap { $0 as? [String: Any] }.map { item in
            switch item["type"] as? String {
            case "text":
                styled(item["text"] as? String ?? "", styles: item["styles"] as? [String: Any] ?? [:])
            case "link":
                "[\(inline(item["content"], lineBreak: " "))](\(item["href"] as? String ?? ""))"
            case "hardBreak":
                lineBreak
            default:
                ""
            }
        }
        .joined()
    }

    /// Text of a code block, as is.
    private static func plain(_ content: Any?) -> String {
        (content as? [Any] ?? []).compactMap { $0 as? [String: Any] }.map { item in
            item["type"] as? String == "hardBreak" ? "\n" : item["text"] as? String ?? ""
        }
        .joined()
    }

    private static func styled(_ text: String, styles: [String: Any]) -> String {
        guard !text.isEmpty else {
            return ""
        }
        if styles["code"] as? Bool == true {
            return "`" + text.replacingOccurrences(of: "`", with: "'") + "`"
        }
        var result = escaped(text)
        if styles["strikethrough"] as? Bool == true {
            result = "~~\(result)~~"
        }
        if styles["italic"] as? Bool == true {
            result = "_\(result)_"
        }
        if styles["bold"] as? Bool == true {
            result = "**\(result)**"
        }
        return result
    }

    /// Characters Markdown would read as formatting.
    private static func escaped(_ text: String) -> String {
        var result = ""
        for character in text {
            if "\\*_`[]".contains(character) {
                result.append("\\")
            }
            result.append(character)
        }
        return result
    }
}
