import Foundation

/// Where Matcha copies page addresses (“Copy Link”, ⇧⌘C, history rows): the system's (`Clipboard.system`, one per
/// platform: `Clipboard+AppKit`), or a private one in tests.
@MainActor
struct Clipboard {
    /// Replaces the contents with `urls`, never empty: one URL per address, and the text with one address per line.
    let write: ([URL]) -> Void

    func copy(_ url: URL) {
        write([url])
    }

    /// Several addresses (history rows); nothing for none.
    func copy(_ urls: [URL]) {
        if !urls.isEmpty {
            write(urls)
        }
    }
}
