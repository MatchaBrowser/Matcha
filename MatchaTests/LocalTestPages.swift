import Foundation

/// Two local pages (`file:`) written by the test in a folder of its own, erased with it (review TS5): no test depends
/// on a file shipped with macOS (`/usr/share/doc`), which would skip it without failing if it were gone. Held by the
/// test (a property of its type).
final class LocalTestPages: @unchecked Sendable {
    static let indexTitle = "Local Documentation"
    static let secondTitle = "Basic Configuration"

    let folder = FileManager.default.temporaryDirectory.appending(path: "LocalTestPages-\(UUID().uuidString)")

    /// First page, with a link to the second.
    var index: URL {
        folder.appending(path: "index.html")
    }

    var second: URL {
        folder.appending(path: "second.html")
    }

    init() {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? Self.page(Self.indexTitle, body: "<a href='second.html'>Next</a>").write(to: index)
        try? Self.page(Self.secondTitle, body: "<p>Second page</p>").write(to: second)
    }

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    private static func page(_ title: String, body: String) -> Data {
        Data("<!doctype html><html><head><title>\(title)</title></head><body>\(body)</body></html>".utf8)
    }
}
