import Foundation
@testable import Matcha
import Testing

/// What a local page may read (audit W6): its folder when the user opens it, never more than the linking page's.
struct FileReadAccessTests {
    private let file = URL(filePath: "/Users/moi/Documents/docs/guide/page.html")

    @Test func `a file the user opens reads its folder`() {
        #expect(FileReadAccess.readableURL(for: file, openedFrom: nil) == file.deletingLastPathComponent())
    }

    @Test func `a file linked from a website only reads itself`() {
        let website = URL(string: "https://example.com/")
        #expect(FileReadAccess.readableURL(for: file, openedFrom: website) == file)
    }

    @Test(arguments: [
        ("/Users/moi/Documents/docs/guide/index.html", true),
        ("/Users/moi/Documents/docs/index.html", true),
        ("/Users/moi/Documents/docs/guide/../index.html", true),
        ("/Users/moi/Documents/docs/guide/plus/index.html", false),
        ("/Users/moi/Documents/doc/index.html", false),
        ("/Users/moi/Downloads/piege.html", false),
    ])
    func `a file linked from a local page reads its folder only inside that page's`(source: String, readsFolder: Bool) {
        let readable = FileReadAccess.readableURL(for: file, openedFrom: URL(filePath: source))
        #expect(readable == (readsFolder ? file.deletingLastPathComponent() : file))
    }
}
