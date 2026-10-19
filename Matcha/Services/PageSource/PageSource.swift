import Foundation

/// Source code of a page (“View Page Source” in a page's menu), with no dependency on the UI: address of the viewer
/// (`matcha-source:https://…`, which finds its page again after a relaunch, like `view-source:` in Chrome), text read
/// in the response's encoding, and HTML page that shows it, line by line and numbered, without any script.
nonisolated enum PageSource {
    static let scheme = "matcha-source"
    /// Pages whose source code can be shown.
    static let sourceSchemes: Set<String> = ["http", "https", "file"]

    /// Address of the source code viewer of `page`; nil for a page that has none (about:, data:…).
    static func viewerURL(for page: URL?) -> URL? {
        guard let page, let scheme = page.scheme?.lowercased(), sourceSchemes.contains(scheme) else {
            return nil
        }
        return URL(string: "\(Self.scheme):\(page.absoluteString)")
    }

    /// Page whose source code `viewer` shows.
    static func pageURL(fromViewer viewer: URL) -> URL? {
        guard viewer.scheme?.lowercased() == scheme else {
            return nil
        }
        let page = URL(string: String(viewer.absoluteString.dropFirst(scheme.count + 1)))
        guard let page, let pageScheme = page.scheme?.lowercased(), sourceSchemes.contains(pageScheme) else {
            return nil
        }
        return page
    }

    /// Text of `data`, in the encoding announced by the response (`charset`), otherwise UTF-8, otherwise Latin-1
    /// (which reads everything).
    static func text(of data: Data, textEncodingName: String?) -> String {
        if let encoding = encoding(named: textEncodingName), let text = String(bytes: data, encoding: encoding) {
            return text
        }
        return String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
    }

    private static func encoding(named name: String?) -> String.Encoding? {
        guard let name else {
            return nil
        }
        let encoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard encoding != kCFStringEncodingInvalidId else {
            return nil
        }
        return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))
    }

    /// Page that shows `source`: one numbered line per line of the text, escaped; no script can run in it.
    static func viewerHTML(source: String, title: String) -> String {
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { "<li>\($0.isEmpty ? " " : escaped(String($0)))</li>" }
        return document(title: title, body: "<ol>\(lines.joined(separator: "\n"))</ol>")
    }

    /// Error page of the viewer.
    static func errorHTML(title: String, message: String, detail: String) -> String {
        document(title: title, body: "<p class=\"error\">\(escaped(message))</p><p class=\"detail\">\(escaped(detail))</p>")
    }

    static func escaped(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            default: result.append(character)
            }
        }
        return result
    }

    private static func document(title: String, body: String) -> String {
        """
        <!doctype html>
        <html><head><meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'">
        <meta name="color-scheme" content="light dark">
        <title>\(escaped(title))</title>
        <style>
        body { margin: 0; font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace; }
        ol { margin: 0; padding: 8px 12px 8px 5em; }
        li { white-space: pre-wrap; word-break: break-all; padding-left: 1em; }
        li::marker { color: GrayText; font-size: 11px; }
        p { margin: 24px; font-family: -apple-system, sans-serif; font-size: 14px; }
        .detail { color: GrayText; }
        </style></head>
        <body>\(body)</body></html>
        """
    }
}
