import Foundation

/// What a local page may read (`loadFileURL(_:allowingReadAccessTo:)`, audit W6). A file the user opens (address bar,
/// restored tab) reads its folder, for its images and style sheets. A file opened by a link from another page (new
/// tab, Peek) reads its folder only if that folder is inside the linking page's; otherwise only itself: a page can't
/// widen its own access. Pure type.
nonisolated enum FileReadAccess {
    static func readableURL(for file: URL, openedFrom source: URL?) -> URL {
        let folder = file.deletingLastPathComponent()
        guard let source else {
            return folder
        }
        guard source.isFileURL else {
            return file
        }
        let sourceFolder = source.deletingLastPathComponent().standardizedFileURL.path
        let target = folder.standardizedFileURL.path
        let prefix = sourceFolder.hasSuffix("/") ? sourceFolder : sourceFolder + "/"
        return target == sourceFolder || target.hasPrefix(prefix) ? folder : file
    }
}
