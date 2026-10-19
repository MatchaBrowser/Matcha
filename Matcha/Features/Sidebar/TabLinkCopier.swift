import AppKit

/// Copies a page's address to the pasteboard, as a URL and as text.
@MainActor
enum TabLinkCopier {
    static func copy(_ url: URL, to pasteboard: NSPasteboard = .general) {
        copy([url], to: pasteboard)
    }

    /// Several addresses (history rows): one URL per address, and the text with one address per line.
    static func copy(_ urls: [URL], to pasteboard: NSPasteboard = .general) {
        guard !urls.isEmpty else {
            return
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        pasteboard.setString(urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
    }
}
