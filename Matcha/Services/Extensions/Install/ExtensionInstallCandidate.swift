import Foundation
import WebKit

/// Extension ready to install, waiting for the user's approval (permissions screen, task 6.4).
struct ExtensionInstallCandidate: Identifiable {
    enum Source {
        /// Chosen file or folder: unpacked into `staging`, manifest in `root`.
        case package(root: URL, staging: URL, fileName: String)
        /// Safari extension of an app, loaded in place.
        case appExtension(SafariAppExtension)
    }

    /// What installing it does to the installed extensions (audit E1).
    enum Mode: Equatable {
        /// Another extension, under an identifier of its own.
        case new
        /// The same extension, from the same verified publisher (or the same app): it replaces the installed version
        /// and keeps its data and decisions.
        case update(previousVersion: String?)
        /// Same name as an installed extension, without proof that it comes from the same developer: it replaces
        /// that one, whose data is erased.
        case replacement(identifier: String, previousVersion: String?)
    }

    /// Where it installs: the installed extension's identifier for an update, a new one otherwise.
    let identifier: String
    let webExtension: WKWebExtension
    let source: Source
    let mode: Mode
    /// Publisher proven by the file's signature (`CRXSignature`); nil if it can't be proven.
    var publisher: String?
    /// For an app's Safari extension: its signed identity, read once, off the main thread (review EX7).
    var appExtensionIdentity: String?
    /// For an update: what the installed version couldn't do, and whether it had private windows.
    var addedSummary: [ExtensionPermissionSummary.Line] = []
    var allowedPrivateWindows = false

    var id: String {
        identifier
    }

    var isUpdate: Bool {
        if case .update = mode {
            return true
        }
        return false
    }

    /// What the extension will be able to do, for the permissions screen.
    var summary: [ExtensionPermissionSummary.Line] {
        Self.summary(of: webExtension)
    }

    static func summary(of webExtension: WKWebExtension, minus previous: WKWebExtension? = nil) -> [ExtensionPermissionSummary.Line] {
        let permissions = Set(webExtension.requestedPermissions.map(\.rawValue))
            .subtracting(previous.map { Set($0.requestedPermissions.map(\.rawValue)) } ?? [])
        let previousPatterns = Set(previous?.requestedPermissionMatchPatterns.map(\.string) ?? [])
        let patterns = webExtension.requestedPermissionMatchPatterns.filter { !previousPatterns.contains($0.string) }
        return ExtensionPermissionSummary.lines(
            permissions: permissions,
            hosts: patterns.filter { $0.scheme != "file" }.map { $0.matchesAllHosts ? nil : $0.host },
            readsLocalFiles: patterns.contains { $0.scheme == "file" || $0.matchesAllURLs },
        )
    }
}
