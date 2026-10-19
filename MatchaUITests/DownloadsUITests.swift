import XCTest

/// Downloads (task 5.1): list, real quarantined file, private window, hidden sidebar. Without network; files
/// written to ~/Downloads/MatchaUITests then deleted (see `UITestSupport+Downloads`). Button always visible,
/// empty panel and ⌥⌘L: `DownloadsPanelUITests`.
final class DownloadsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Launches the app on the test folder; it is deleted at the end of the test, even on failure.
    @MainActor
    private func launchForDownloads() -> XCUIApplication {
        addTeardownBlock { @MainActor in
            self.removeDownloadsTestFolder()
        }
        let app = launchApp(settings: Self.downloadsTestSettings)
        XCTAssertTrue(waitForBrowserWindow(of: app))
        return app
    }

    @MainActor
    func testUndisplayableFileIsDownloadedQuarantinedAndListed() throws {
        let source = try undisplayableFile()
        let name = URL(fileURLWithPath: source).lastPathComponent
        let app = launchForDownloads()
        let button = downloadsButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        let file = downloadsTestFolder.appendingPathComponent(name)

        download(source, in: app)
        XCTAssertTrue(waitForFile(file))
        // Nothing opens by itself: neither the list nor the file.
        XCTAssertFalse(downloadsPanel(in: app).waitForExistence(timeout: 1))

        button.click()
        XCTAssertTrue(downloadsPanel(in: app).waitForExistence(timeout: 3))
        let row = downloadRows(in: app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertFalse(downloadsEmptyState(in: app).exists)
        XCTAssertEqual(downloadRows(in: app).count, 1)
        XCTAssertEqual(row.label, name)
        // Finished: “Show in Finder” replaces “Cancel”.
        XCTAssertTrue(row.buttons["downloadShowInFinderButton"].waitForExistence(timeout: 20))
        XCTAssertFalse(row.buttons["downloadCancelButton"].exists)

        // Outside the app: the real file, complete, quarantined in Matcha's name.
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int
        XCTAssertEqual(size, try FileManager.default.attributesOfItem(atPath: source)[.size] as? Int)
        let quarantine = try XCTUnwrap(quarantineAttribute(of: file), "Fichier sans attribut de quarantaine")
        XCTAssertTrue(quarantine.contains(";Matcha;"), quarantine)

        // “Clear” empties the list without touching the file: the panel stays open, empty, and “Clear” is grayed out;
        // the button stays.
        let clear = app.buttons["downloadsClearButton"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        XCTAssertTrue(clear.isEnabled)
        clear.click()
        XCTAssertTrue(row.waitForNonExistence(timeout: 3))
        XCTAssertTrue(downloadsEmptyState(in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(downloadsPanel(in: app).exists)
        XCTAssertFalse(clear.isEnabled)
        XCTAssertTrue(button.exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        app.terminate()
    }

    /// The same file twice: “name.ext” then “name 2.ext”, the most recent first; nothing is overwritten.
    @MainActor
    func testSameFileTwiceGetsANumberedName() throws {
        let source = try undisplayableFile()
        let (base, pathExtension) = splitName(URL(fileURLWithPath: source).lastPathComponent)
        let app = launchForDownloads()

        download(source, in: app)
        XCTAssertTrue(waitForFile(downloadsTestFolder.appendingPathComponent("\(base)\(pathExtension)")))
        download(source, in: app)
        downloadsButton(in: app).click()
        XCTAssertTrue(waitForCount(downloadRows(in: app), 2, timeout: 10))

        let labels = downloadRows(in: app).allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(labels, ["\(base) 2\(pathExtension)", "\(base)\(pathExtension)"])
        for label in labels {
            XCTAssertTrue(FileManager.default.fileExists(atPath: downloadsTestFolder.appendingPathComponent(label).path), label)
        }
        app.terminate()
    }

    /// A private window has its own list, which the main window doesn't show; when it closes, the file stays in the
    /// folder and the list is forgotten (also checked by `DownloadManagerTests`).
    @MainActor
    func testPrivateWindowHasItsOwnDownloadsList() throws {
        let source = try undisplayableFile()
        let app = launchForDownloads()
        // Main window panel opened first: it stays visible behind the private window.
        let mainWindow = app.windows.matching(NSPredicate(format: "title != %@", "Navigation privée")).firstMatch
        downloadsButton(in: mainWindow).click()
        XCTAssertTrue(downloadsEmptyState(in: mainWindow).waitForExistence(timeout: 3))
        let privateWindow = openPrivateWindow(in: app)
        XCTAssertTrue(downloadsButton(in: privateWindow).exists)

        download(source, in: app, window: privateWindow)
        let file = downloadsTestFolder.appendingPathComponent(URL(fileURLWithPath: source).lastPathComponent)
        XCTAssertTrue(waitForFile(file))
        downloadsButton(in: privateWindow).click()
        XCTAssertTrue(waitForCount(downloadRows(in: privateWindow), 1))
        // The main window doesn't show the private downloads.
        XCTAssertEqual(downloadRows(in: mainWindow).count, 0)
        XCTAssertTrue(downloadsEmptyState(in: mainWindow).exists)

        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(privateWindow.waitForNonExistence(timeout: 5))
        XCTAssertTrue(downloadsButton(in: app).exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        // A new private window starts without a list: button present, panel closed, empty once opened.
        let newPrivateWindow = openPrivateWindow(in: app)
        let newButton = downloadsButton(in: newPrivateWindow)
        XCTAssertTrue(newButton.waitForExistence(timeout: 3))
        XCTAssertFalse(downloadsPanel(in: newPrivateWindow).exists)
        newButton.click()
        XCTAssertTrue(downloadsEmptyState(in: newPrivateWindow).waitForExistence(timeout: 3))
        XCTAssertEqual(downloadRows(in: newPrivateWindow).count, 0)
        app.terminate()
    }

    /// Hidden sidebar: the panel moves up into the floating sidebar, hides with it when the pointer moves away,
    /// reappears open with it; the cross closes it.
    @MainActor
    func testDownloadsPanelFollowsTheHiddenSidebar() throws {
        let source = try undisplayableFile()
        let app = launchForDownloads()
        let window = app.windows.firstMatch
        download(source, in: app)
        XCTAssertTrue(waitForFile(downloadsTestFolder.appendingPathComponent(URL(fileURLWithPath: source).lastPathComponent)))
        let button = downloadsButton(in: app)
        XCTAssertTrue(button.exists)

        moveAwayFromLeftEdge(in: window)
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(button.waitForNonExistence(timeout: 3))
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 3, dy: 0))
        edge.hover()
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.click()
        let row = downloadRows(in: app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))

        // Far from the edge: the sidebar hides, panel included.
        moveAwayFromLeftEdge(in: window)
        XCTAssertTrue(button.waitForNonExistence(timeout: 3))
        XCTAssertFalse(row.exists)
        // Back at the edge: the panel is still open.
        edge.hover()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        clickWhenSettled(app.buttons["downloadsCloseButton"])
        XCTAssertTrue(row.waitForNonExistence(timeout: 3))
        XCTAssertTrue(button.exists)
        app.terminate()
    }

    /// The runner only reads: it waits for the app to have written the file.
    private func waitForFile(_ file: URL, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate { _, _ in FileManager.default.fileExists(atPath: file.path) }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout) == .completed
    }

    /// “less.1.gz” → (“less.1”, “.gz”): like the app, for a simple extension.
    private func splitName(_ name: String) -> (String, String) {
        let url = URL(fileURLWithPath: name)
        let pathExtension = url.pathExtension
        return pathExtension.isEmpty ? (name, "") : (url.deletingPathExtension().lastPathComponent, ".\(pathExtension)")
    }
}
