import AppKit

extension Clipboard {
    /// The Mac's general pasteboard.
    static var system: Clipboard {
        Clipboard(.general)
    }

    /// Writes to `pasteboard` (tests: a pasteboard of their own).
    init(_ pasteboard: NSPasteboard) {
        self.init { urls in
            pasteboard.clearContents()
            pasteboard.writeObjects(urls.map { $0 as NSURL })
            pasteboard.setString(urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
        }
    }
}
