import Foundation
import XCTest

/// Helpers for the downloads tests (task 5.1), without network: a file written by the tests that WebKit doesn't
/// display (`UITestPages`), opened from the command bar, is downloaded.
///
/// The app writes to ~/Downloads/MatchaUITests (arguments `downloadsSubfolder` and `resetDownloadsSubfolder`),
/// never next to the user's files. The test runner is sandboxed by Xcode, read-only on the whole disk: it reads
/// the file and its quarantine attribute, but can't delete anything. It is the app, relaunched with
/// `resetDownloadsSubfolder`, that deletes the folder (`removeDownloadsTestFolder`, at the end of each test).
extension XCTestCase {
    static let downloadsTestFolderName = "MatchaUITests"
    /// Launch settings: downloads in the test folder, emptied at launch.
    static let downloadsTestSettings = ["downloadsSubfolder": downloadsTestFolderName, "resetDownloadsSubfolder": "YES"]

    /// ~/Downloads/MatchaUITests, in the real home folder (the sandboxed runner's one is its container).
    var downloadsTestFolder: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Downloads").appendingPathComponent(Self.downloadsTestFolderName)
    }

    /// File to download, written by the tests.
    func undisplayableFile() throws -> String {
        UITestPages.undisplayable
    }

    /// Opens `path` (local file) in a new tab of `window` (the app if nil): it gets downloaded.
    @MainActor
    func download(_ path: String, in app: XCUIApplication, window: XCUIElement? = nil) {
        let field = openCommandBar(in: app, window: window)
        app.typeText("file://\(path)\n")
        XCTAssertTrue(field.waitForNonExistence(timeout: 3))
    }

    @MainActor
    func downloadsButton(in scope: XCUIElement) -> XCUIElement {
        scope.buttons["downloadsButton"]
    }

    /// `scope`: the app, or a specific window (each window has its own panel).
    @MainActor
    func downloadsPanel(in scope: XCUIElement) -> XCUIElement {
        scope.descendants(matching: .any).matching(identifier: "downloadsPanel").firstMatch
    }

    @MainActor
    func downloadRows(in scope: XCUIElement) -> XCUIElementQuery {
        scope.descendants(matching: .any).matching(identifier: "downloadRow")
    }

    /// “No Downloads” text of the empty panel.
    @MainActor
    func downloadsEmptyState(in scope: XCUIElement) -> XCUIElement {
        scope.descendants(matching: .any).matching(identifier: "downloadsEmptyState").firstMatch
    }

    /// “Show Downloads Folder” button of the empty panel; never clicked by the tests (it would open the
    /// Finder). Looked up by its identifier only: its link style may make it a link for accessibility.
    @MainActor
    func downloadsShowFolderButton(in scope: XCUIElement) -> XCUIElement {
        scope.descendants(matching: .any).matching(identifier: "downloadsShowFolderButton").firstMatch
    }

    /// View > “Show Downloads” / “Hide Downloads” (⌥⌘L).
    @MainActor
    func toggleDownloadsWithKeyboard(in app: XCUIApplication) {
        app.typeKey("l", modifierFlags: [.command, .option])
    }

    /// Value of `com.apple.quarantine` (“flags;date;app;event”), nil if the file doesn't carry it.
    func quarantineAttribute(of file: URL) -> String? {
        let length = getxattr(file.path, "com.apple.quarantine", nil, 0, 0, 0)
        guard length > 0 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: length)
        guard getxattr(file.path, "com.apple.quarantine", &buffer, length, 0, 0) == length else {
            return nil
        }
        return String(bytes: buffer, encoding: .utf8)
    }

    /// Relaunches the app with `resetDownloadsSubfolder`: it deletes the test folder at launch, then quits.
    @MainActor
    func removeDownloadsTestFolder() {
        let app = launchApp(settings: Self.downloadsTestSettings)
        _ = waitForBrowserWindow(of: app)
        app.terminate()
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloadsTestFolder.path), "Test folder not erased")
    }
}
