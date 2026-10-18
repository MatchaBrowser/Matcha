import XCTest

/// Panneau des téléchargements sans téléchargement (tâche 5.1, après essai) : bouton toujours visible dans le pied de la
/// barre, panneau vide avec « Aucun téléchargement » et le bouton du dossier Téléchargements (jamais cliqué : il
/// ouvrirait le Finder), Présentation > « Afficher les téléchargements » (⌥⌘L). Rien n'est téléchargé.
final class DownloadsPanelUITests: XCTestCase {
    private let showTitle = "Afficher les téléchargements"
    private let hideTitle = "Masquer les téléchargements"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Le bouton est là dès le lancement, rien ne s'ouvre de soi-même ; un clic ouvre le panneau vide, la croix le
    /// ferme et le bouton reste. Même chose dans une fenêtre privée.
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
        // Texte lu dans le libellé ou dans la valeur, selon la version de macOS.
        XCTAssertTrue([emptyState.label, emptyState.value as? String].contains("Aucun téléchargement"))
        XCTAssertTrue(downloadsShowFolderButton(in: app).exists)
        XCTAssertEqual(downloadRows(in: app).count, 0)
        // Rien à effacer.
        let clear = app.buttons["downloadsClearButton"]
        XCTAssertTrue(clear.exists)
        XCTAssertFalse(clear.isEnabled)

        clickWhenSettled(app.buttons["downloadsCloseButton"])
        XCTAssertTrue(downloadsPanel(in: app).waitForNonExistence(timeout: 3))
        XCTAssertTrue(button.exists)
        // Le bouton referme aussi le panneau.
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

    /// ⌥⌘L ouvre puis ferme le panneau ; le titre du menu suit. Grisé quand les Réglages sont au premier plan.
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

    /// Barre masquée (⌘S) : ⌥⌘L l'affiche d'abord, puis ouvre le panneau dedans.
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
        // La barre reste affichée, même loin du bord gauche.
        moveAwayFromLeftEdge(in: window)
        XCTAssertFalse(newTabButton.waitForNonExistence(timeout: 1))
        XCTAssertTrue(waitForMenuItem("Masquer la barre latérale", enabled: true, in: app))
        XCTAssertTrue(waitForMenuItem(hideTitle, enabled: true, in: app))
        app.terminate()
    }
}
