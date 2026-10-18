import Foundation

/// Code source d'une page (« Afficher le code source » du menu d'une page), sans dépendance à l'interface : adresse du
/// visualiseur (`matcha-source:https://…`, qui retrouve sa page après un relancement, comme `view-source:` dans Chrome),
/// texte lu dans l'encodage de la réponse, et page HTML qui le montre, ligne par ligne et numérotée, sans aucun script.
nonisolated enum PageSource {
    static let scheme = "matcha-source"
    /// Pages dont on peut afficher le code source.
    static let sourceSchemes: Set<String> = ["http", "https", "file"]

    /// Adresse du visualiseur du code source de `page` ; nil pour une page qui n'en a pas (about:, data:…).
    static func viewerURL(for page: URL?) -> URL? {
        guard let page, let scheme = page.scheme?.lowercased(), sourceSchemes.contains(scheme) else {
            return nil
        }
        return URL(string: "\(Self.scheme):\(page.absoluteString)")
    }

    /// Page dont `viewer` montre le code source.
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

    /// Texte de `data`, dans l'encodage annoncé par la réponse (`charset`), sinon UTF-8, sinon Latin-1 (qui lit tout).
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

    /// Page qui montre `source` : une ligne numérotée par ligne du texte, échappée ; aucun script ne peut s'y exécuter.
    static func viewerHTML(source: String, title: String) -> String {
        let lines = source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            .map { "<li>\($0.isEmpty ? " " : escaped(String($0)))</li>" }
        return document(title: title, body: "<ol>\(lines.joined(separator: "\n"))</ol>")
    }

    /// Page d'erreur du visualiseur.
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
