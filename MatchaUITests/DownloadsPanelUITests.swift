import XCTest

/// Downloads panel without any download (task 5.1, after trying it): button always visible in the sidebar footer,
/// empty panel with “No Downloads” and the Downloads folder button (never clicked: it would open the Finder),
/// View > “Show Downloads” (⌥⌘L). Nothing is downloaded.
final class DownloadsPanelUITests: XCTestCase {
    private let showTitle = "Afficher les téléchargements"
    private let hideTitle = "Masquer les téléchargements"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The button is there from launch, nothing opens by itself; a click opens the empty panel, the cross closes it
    /// and the button stays. Same in a private window.
    @MainActor
    func testButtonIsAlwaysVisibleAndOpensAnEmptyPanel() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        let button = downloadsButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        XCTAssertFalse(downloadsPanel(in: app).waitForExistence(timeout: 1))

        button.click()
        XCTAssertTrue(downloadsPanel(in: app).waitForExistence(timeout: 3))
        let emptyState = downloadsEmptyState(in: app)
        XCTAssertTrue(emptyState.waitForExistence(timeout: 3))
        // Text read from the label or the value, depending on the macOS version.
        XCTAssertTrue([emptyState.label, emptyState.value as? String].contains("Aucun téléchargement"))
        XCTAssertTrue(downloadsShowFolderButton(in: app).exists)
        XCTAssertEqual(downloadRows(in: app).count, 0)
        // Nothing to clear.
        let clear = app.buttons["downloadsClearButton"]
        XCTAssertTrue(clear.exists)
        XCTAssertFalse(clear.isEnabled)

        clickWhenSettled(app.buttons["downloadsCloseButton"])
        XCTAssertTrue(downloadsPanel(in: app).waitForNonExistence(timeout: 3))
        XCTAssertTrue(button.exists)
        // The button also closes the panel.
        button.click()
        XCTAssertTrue(downloadsPanel(in: app).waitForExistence(timeout: 3))
        button.click()
        XCTAssertTrue(downloadsPanel(in: app).waitForNonExistence(timeout: 3))

        let privateWindow = openPrivateWindow(in: app)
        let privateButton = downloadsButton(in: privateWindow)
        XCTAssertTrue(privateButton.waitForExistence(timeout: 3))
        privateButton.click()
        XCTAssertTrue(downloadsEmptyState(in: privateWindow).waitForExistence(timeout: 3))
        XCTAssertTrue(downloadsShowFolderButton(in: privateWindow).exists)
        app.terminate()
    }

    /// ⌥⌘L opens then closes the panel; the menu title follows. Grayed out when Settings is in front.
    @MainActor
    func testCommandOptionLTogglesThePanel() {
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        XCTAssertTrue(waitForMenuItem(showTitle, enabled: true, in: app))

        toggleDownloadsWithKeyboard(in: app)
        XCTAssertTrue(downloadsPanel(in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(downloadsEmptyState(in: app).exists)
        XCTAssertTrue(waitForMenuItem(hideTitle, enabled: true, in: app))

        toggleDownloadsWithKeyboard(in: app)
        XCTAssertTrue(downloadsPanel(in: app).waitForNonExistence(timeout: 3))
        XCTAssertTrue(waitForMenuItem(showTitle, enabled: true, in: app))

        app.typeKey(",", modifierFlags: .command)
        XCTAssertTrue(app.toolbars.buttons["Général"].waitForExistence(timeout: 5))
        XCTAssertTrue(waitForMenuItem(showTitle, enabled: false, in: app))
        app.terminate()
    }

    /// Hidden sidebar (⌘S): ⌥⌘L shows it first, then opens the panel in it.
    @MainActor
    func testCommandOptionLShowsTheHiddenSidebarAndThePanel() {
        let app = launchApp()
        let window = app.windows.firstMatch
        let newTabButton = app.buttons["newTabButton"]
        XCTAssertTrue(newTabButton.waitForExistence(timeout: 5))
        moveAwayFromLeftEdge(in: window)
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(newTabButton.waitForNonExistence(timeout: 3))
        XCTAssertFalse(downloadsButton(in: app).exists)

        toggleDownloadsWithKeyboard(in: app)
        XCTAssertTrue(newTabButton.waitForExistence(timeout: 3))
        XCTAssertTrue(downloadsPanel(in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(downloadsEmptyState(in: app).exists)
        // The sidebar stays shown, even far from the left edge.
        moveAwayFromLeftEdge(in: window)
        XCTAssertFalse(newTabButton.waitForNonExistence(timeout: 1))
        XCTAssertTrue(waitForMenuItem("Masquer la barre latérale", enabled: true, in: app))
        XCTAssertTrue(waitForMenuItem(hideTitle, enabled: true, in: app))
        app.terminate()
    }
}
