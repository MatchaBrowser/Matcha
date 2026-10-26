import Foundation

/// What a local page may read (`loadFileURL(_:allowingReadAccessTo:)`, audit W6). A file the user opens in Matcha
/// (address bar, ⌘O) reads its folder, for its images and style sheets. A file opened by a link from another page (new
/// tab, Peek) reads its folder only if that folder is inside the linking page's, links resolved; otherwise only itself:
/// a page can't widen its own access. A file received from another app (Finder, `open`: any process can send one) reads
/// only itself (review WB11). The tab keeps the access granted, for its reloads and after a relaunch. Pure type.
nonisolated enum FileReadAccess {
    /// `source`: the page whose link it is; nil if the user opened the file in Matcha.
    static func readableURL(for file: URL, openedFrom source: URL?, isFromAnotherApp: Bool = false) -> URL {
        let folder = file.deletingLastPathComponent()
        if isFromAnotherApp {
            return file
        }
        guard let source else {
            return folder
        }
        guard source.isFileURL else {
            return file
        }
        let sourceFolder = resolved(source.deletingLastPathComponent())
        let target = resolved(folder)
        return target == sourceFolder || target.hasPrefix(sourceFolder + "/") ? folder : file
    }

    /// True if `access` (a file, or a folder) lets `file` be read: the access a tab keeps (review WB11).
    static func covers(_ access: URL, _ file: URL) -> Bool {
        let access = resolved(access)
        let file = resolved(file)
        return file == access || file.hasPrefix(access + "/")
    }

    /// True if `access` lets the page `file` read nothing but itself (review WB11).
    static func isLimitedToItself(_ access: URL, file: URL) -> Bool {
        resolved(access) == resolved(file)
    }

    /// Path with its symbolic links resolved, without a final “/” (review WB11): a link inside a folder can lead
    /// anywhere. The links of the deepest folder that exists: the system resolves nothing in a path that doesn't.
    private static func resolved(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path), existing.pathComponents.count > 1 {
            rest.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        let path = rest.reduce(existing.resolvingSymlinksInPath()) { $0.appending(path: $1) }.path
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
