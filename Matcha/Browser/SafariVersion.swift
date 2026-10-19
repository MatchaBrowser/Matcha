import Foundation

/// Safari version that the user agent announces (audit H5): that of the installed Safari, which comes with the WebKit
/// the app uses (Safari updates it on older systems too); without it, the one of macOS (Safari 18 on macOS 15, then
/// the same number as macOS from 26). Never a version written in the code, that would age. Pure type.
nonisolated enum SafariVersion {
    static func announced(installed: String?, system: OperatingSystemVersion) -> String {
        if let installed, isVersion(installed) {
            return installed
        }
        let major = system.majorVersion >= 26 ? system.majorVersion : 18
        return "\(major).\(system.majorVersion >= 15 ? system.minorVersion : 0)"
    }

    /// Version of the Safari installed on this Mac (`/Applications/Safari.app`, a link to the system's).
    static func installed() -> String? {
        Bundle(path: "/Applications/Safari.app")?.infoDictionary?["CFBundleShortVersionString"] as? String
    }

    /// “26”, “26.6”, “26.6.2”: digits separated by dots.
    private static func isVersion(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return (1 ... 3).contains(parts.count) && parts.allSatisfy { !$0.isEmpty && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }
    }
}
