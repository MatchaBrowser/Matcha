import Foundation

/// The page of the notes editor and its files (task 12.2), served under `matcha-note://editor/` by
/// `NoteEditorSchemeHandler` from the app's resources (`Resources/NoteEditor`, which Xcode copies flat; the subfolder is
/// also searched). The script and the style sheet come from `scripts/build-note-editor.sh`. Pure type.
nonisolated enum NoteEditorResources {
    static let scheme = "matcha-note"
    static let host = "editor"
    static let pageAddress = "matcha-note://editor/note-editor.html"
    static let subdirectory = "NoteEditor"
    /// Largest file served: the script is about 550 KB.
    static let maximumSize = 4 * 1024 * 1024
    /// Same policy as the page's `<meta>`: the app's script and styles only (inline styles too: the colors of the text
    /// are style attributes), the check mark's `data:` image, no network, no frame, no form.
    static let contentSecurityPolicy = "default-src 'none'; script-src matcha-note:; style-src matcha-note: 'unsafe-inline'; " +
        "img-src data:; connect-src 'none'; media-src 'none'; frame-src 'none'; object-src 'none'; base-uri 'none'; " +
        "form-action 'none'"

    struct File: Equatable, Sendable {
        let name: String
        let mimeType: String
    }

    /// The files served, by path; any other address is refused.
    static let files: [String: File] = [
        "/note-editor.html": File(name: "note-editor.html", mimeType: "text/html"),
        "/note-editor.js": File(name: "note-editor.js", mimeType: "text/javascript"),
        "/note-editor.css": File(name: "note-editor.css", mimeType: "text/css"),
    ]

    /// File at `url`; nil for an address outside `matcha-note://editor/`, or a path not served.
    static func file(for url: URL) -> File? {
        guard url.scheme?.lowercased() == scheme, url.host()?.lowercased() == host, url.query() == nil else {
            return nil
        }
        return files[url.path()]
    }

    /// True for the page itself, the only navigation the editor's web view makes.
    static func isPage(_ url: URL) -> Bool {
        file(for: url)?.name == "note-editor.html"
    }

    static func headers(for file: File) -> [String: String] {
        [
            "Content-Type": "\(file.mimeType); charset=utf-8",
            "Content-Security-Policy": contentSecurityPolicy,
            "Cache-Control": "no-store",
            "X-Content-Type-Options": "nosniff",
        ]
    }

    /// Content of `file` in `bundle`; nil if it is missing or larger than `maximumSize`.
    static func data(of file: File, in bundle: Bundle) -> Data? {
        guard let url = bundle.url(forResource: file.name, withExtension: nil, subdirectory: subdirectory)
            ?? bundle.url(forResource: file.name, withExtension: nil),
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size <= maximumSize
        else {
            return nil
        }
        return try? Data(contentsOf: url, options: .mappedIfSafe)
    }
}
