import Foundation
import OSLog

/// Folder where downloads go: the user's Downloads. For UI tests, a subfolder named by a launch argument, emptied
/// at launch if requested: the test runner, sandboxed read-only, cannot delete what the app writes there.
nonisolated enum DownloadLocation {
    /// Launch argument: name of the Downloads subfolder to write to (UI tests).
    static let testSubfolderKey = "downloadsSubfolder"
    /// Launch argument: deletes this subfolder at launch; never Downloads itself.
    static let resetTestSubfolderKey = "resetDownloadsSubfolder"
    /// Only names starting with this are accepted: a mistyped argument never targets a folder of the user.
    static let testSubfolderPrefix = "MatchaUITests"

    /// The user's Downloads folder. In the sandbox, `FileManager` gives the `Downloads` folder of the app's
    /// container, a symbolic link to ~/Downloads (“Downloads Folder” entitlement): it is resolved, so that WebKit
    /// writes to the real folder and the Finder shows it.
    static func userDownloadsDirectory() -> URL? {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.resolvingSymlinksInPath()
    }

    /// Downloads folder for this launch.
    static func directory(defaults: UserDefaults = .standard) -> URL? {
        guard let downloads = userDownloadsDirectory() else {
            return nil
        }
        guard let name = testSubfolderName(defaults: defaults) else {
            return downloads
        }
        return downloads.appendingPathComponent(name, isDirectory: true)
    }

    /// Test subfolder requested at launch, if valid: a single component, prefix `testSubfolderPrefix`.
    static func testSubfolderName(defaults: UserDefaults) -> String? {
        guard let name = TestEnvironment.arguments(defaults)?.string(forKey: testSubfolderKey), name.hasPrefix(testSubfolderPrefix),
              DownloadFileName.sanitized(name) == name
        else {
            return nil
        }
        return name
    }

    /// At app launch: deletes the test subfolder if `resetDownloadsSubfolder` asks for it.
    static func resetTestSubfolderIfRequested(defaults: UserDefaults = .standard) {
        guard TestEnvironment.arguments(defaults)?.bool(forKey: resetTestSubfolderKey) == true,
              let name = testSubfolderName(defaults: defaults),
              let downloads = userDownloadsDirectory()
        else {
            return
        }
        let folder = downloads.appendingPathComponent(name, isDirectory: true)
        guard FileManager.default.fileExists(atPath: folder.path) else {
            return
        }
        do {
            try FileManager.default.removeItem(at: folder)
            Logger.downloads.info("Test downloads folder deleted")
        } catch {
            Logger.downloads.error("Test downloads folder not deleted: \(error.logSummary, privacy: .public)")
        }
    }
}
