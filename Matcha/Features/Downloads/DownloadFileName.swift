import Foundation
import UniformTypeIdentifiers

/// File name of a download, without UI dependency: proposed name made safe, then made unique in the folder
/// (“report.pdf”, “report 2.pdf”, “report 3.pdf”…).
nonisolated enum DownloadFileName {
    /// Fallback name when neither the page nor the address provides one (like Chrome), never translated: it is a
    /// file name.
    static let fallback = "download"
    /// Maximum length of a file name (APFS), in UTF-8 bytes.
    static let maximumLength = 255
    /// Beyond this, what follows the last dot is not an extension (“Notes v1.2 long version”).
    static let maximumExtensionLength = 20
    /// Double extensions kept together: “archive 2.tar.gz”, not “archive.tar 2.gz”.
    static let compoundExtensions = ["tar.gz", "tar.bz2", "tar.xz", "tar.zst", "tar.lz", "tar.lzma", "tar.lz4", "tar.z", "tar.bz"]
    /// Bidirectional controls: they make it possible to disguise an extension (“photo”, U+202E then “gpj.app”
    /// displays as “photoppa.jpg”).
    private static let bidiControls = Set<UInt32>([0x061C, 0x200E, 0x200F]).union(0x202A ... 0x202E).union(0x2066 ... 0x2069)

    /// Name proposed by the page or WebKit, made safe; otherwise the last component of `url` (address with a path:
    /// web or file, not `data:` or `blob:`), otherwise `fallback`. A name without an extension gets the one of the
    /// MIME type if it has one (“README” sent as `text/plain`: “README.txt”).
    static func make(suggested: String?, url: URL?, mimeType: String?) -> String {
        let component = url.flatMap { $0.isFileURL || $0.host() != nil ? $0.lastPathComponent : nil }
        let name = [suggested, component].lazy.compactMap { $0.map(sanitized) }.first { !$0.isEmpty } ?? fallback
        guard split(name).extension.isEmpty, let mimeType,
              let preferred = UTType(mimeType: mimeType)?.preferredFilenameExtension
        else {
            return name
        }
        return fitted(name, suffix: "", extension: "." + preferred)
    }

    /// Last component of a path (`/` or `\`), without control characters or bidirectional controls, `:` replaced
    /// by `-` (the Finder shows it as `/`), without a dot or space at the start (no hidden file), without a space at
    /// the end, and 255 bytes at most, extension included. Empty if nothing is left.
    static func sanitized(_ suggested: String) -> String {
        let component = suggested.split { $0 == "/" || $0 == "\\" }.last.map(String.init) ?? ""
        var scalars = String.UnicodeScalarView()
        // C0 and C1 control characters (line feed, tab, NUL…) and bidirectional controls.
        for scalar in component.unicodeScalars where scalar.properties.generalCategory != .control && !bidiControls.contains(scalar.value) {
            scalars.append(scalar == ":" ? "-" : scalar)
        }
        var name = Substring(String(scalars))
        while let first = name.first, first == "." || first.isWhitespace {
            name.removeFirst()
        }
        while let last = name.last, last.isWhitespace {
            name.removeLast()
        }
        let (base, pathExtension) = split(String(name))
        return fitted(base, suffix: "", extension: pathExtension)
    }

    /// First free name among `name`, “base 2.ext”, “base 3.ext”… `isTaken` tells whether a name is already taken
    /// (existing file, or a download in progress that has not created it yet).
    static func unique(_ name: String, isTaken: (String) -> Bool) -> String {
        guard isTaken(name) else {
            return name
        }
        let (base, pathExtension) = split(name)
        for number in 2 ... 9999 {
            let candidate = fitted(base, suffix: " \(number)", extension: pathExtension)
            if !isTaken(candidate) {
                return candidate
            }
        }
        return fitted(base, suffix: " \(UUID().uuidString)", extension: pathExtension)
    }

    /// Name and extension, dot included (“.pdf”, “.tar.gz”); empty extension if the name has none.
    static func split(_ name: String) -> (base: String, extension: String) {
        let lowercased = name.lowercased()
        if let compound = compoundExtensions.first(where: { lowercased.hasSuffix("." + $0) && lowercased.count > $0.count + 1 }) {
            let index = name.index(name.endIndex, offsetBy: -(compound.count + 1))
            return (String(name[..<index]), String(name[index...]))
        }
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else {
            return (name, "")
        }
        let pathExtension = name[name.index(after: dot)...]
        guard !pathExtension.isEmpty, pathExtension.count <= maximumExtensionLength, !pathExtension.contains(where: \.isWhitespace) else {
            return (name, "")
        }
        return (String(name[..<dot]), String(name[dot...]))
    }

    /// `base` + `suffix` + `pathExtension`, shortening `base` to fit in `maximumLength` bytes.
    private static func fitted(_ base: String, suffix: String, extension pathExtension: String) -> String {
        var base = Substring(base)
        while !base.isEmpty, base.utf8.count + suffix.utf8.count + pathExtension.utf8.count > maximumLength {
            base.removeLast()
        }
        return base + suffix + pathExtension
    }
}
