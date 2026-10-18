import XCTest

/// Téléchargements (tâche 5.1) : liste, vrai fichier en quarantaine, fenêtre privée, barre masquée. Sans réseau ;
/// fichiers écrits dans ~/Downloads/MatchaUITests puis effacés (voir `UITestSupport+Downloads`). Bouton toujours
/// visible, panneau vide et ⌥⌘L : `DownloadsPanelUITests`.
final class DownloadsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Lance l'app sur le dossier de test ; il est effacé à la fin du test, même en échec.
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
        // Rien ne s'ouvre de soi-même : ni la liste, ni le fichier.
        XCTAssertFalse(downloadsPanel(in: app).waitForExistence(timeout: 1))

        button.click()
        XCTAssertTrue(downloadsPanel(in: app).waitForExistence(timeout: 3))
        let row = downloadRows(in: app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertFalse(downloadsEmptyState(in: app).exists)
        XCTAssertEqual(downloadRows(in: app).count, 1)
        XCTAssertEqual(row.label, name)
        // Terminé : « Afficher dans le Finder » remplace « Annuler ».
        XCTAssertTrue(row.buttons["downloadShowInFinderButton"].waitForExistence(timeout: 20))
        XCTAssertFalse(row.buttons["downloadCancelButton"].exists)

        // Hors de l'app : le vrai fichier, complet, en quarantaine au nom de Matcha.
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int
        XCTAssertEqual(size, try FileManager.default.attributesOfItem(atPath: source)[.size] as? Int)
        let quarantine = try XCTUnwrap(quarantineAttribute(of: file), "Fichier sans attribut de quarantaine")
        XCTAssertTrue(quarantine.contains(";Matcha;"), quarantine)

        // « Effacer » vide la liste sans toucher au fichier : le panneau reste ouvert, vide, et « Effacer » se grise ;
        // le bouton reste.
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

    /// Le même fichier deux fois : « nom.ext » puis « nom 2.ext », le plus récent en tête ; rien n'est écrasé.
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

    /// Une fenêtre privée a sa propre liste, que la fenêtre principale ne montre pas ; à sa fermeture, le fichier
    /// reste dans le dossier et la liste est oubliée (vérifié aussi par `DownloadManagerTests`).
    @MainActor
    func testPrivateWindowHasItsOwnDownloadsList() throws {
        let source = try undisplayableFile()
        let app = launchForDownloads()
        // Panneau de la fenêtre principale ouvert d'abord : il reste visible derrière la fenêtre privée.
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
        // La fenêtre principale ne montre pas les téléchargements privés.
        XCTAssertEqual(downloadRows(in: mainWindow).count, 0)
        XCTAssertTrue(downloadsEmptyState(in: mainWindow).exists)

        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(privateWindow.waitForNonExistence(timeout: 5))
        XCTAssertTrue(downloadsButton(in: app).exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        // Une nouvelle fenêtre privée repart sans liste : bouton présent, panneau fermé, vide une fois ouvert.
        let newPrivateWindow = openPrivateWindow(in: app)
        let newButton = downloadsButton(in: newPrivateWindow)
        XCTAssertTrue(newButton.waitForExistence(timeout: 3))
        XCTAssertFalse(downloadsPanel(in: newPrivateWindow).exists)
        newButton.click()
        XCTAssertTrue(downloadsEmptyState(in: newPrivateWindow).waitForExistence(timeout: 3))
        XCTAssertEqual(downloadRows(in: newPrivateWindow).count, 0)
        app.terminate()
    }

    /// Barre masquée : le panneau monte dans la barre flottante, se cache avec elle quand le pointeur s'éloigne,
    /// réapparaît ouvert avec elle ; la croix le ferme.
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

        // Loin du bord : la barre se cache, panneau compris.
        moveAwayFromLeftEdge(in: window)
        XCTAssertTrue(button.waitForNonExistence(timeout: 3))
        XCTAssertFalse(row.exists)
        // De retour au bord : le panneau est toujours ouvert.
        edge.hover()
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        clickWhenSettled(app.buttons["downloadsCloseButton"])
        XCTAssertTrue(row.waitForNonExistence(timeout: 3))
        XCTAssertTrue(button.exists)
        app.terminate()
    }

    /// Le lanceur ne fait que lire : il attend que l'app ait écrit le fichier.
    private func waitForFile(_ file: URL, timeout: TimeInterval = 10) -> Bool {
        let predicate = NSPredicate { _, _ in FileManager.default.fileExists(atPath: file.path) }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: timeout) == .completed
    }

    /// « less.1.gz » → (« less.1 », « .gz ») : comme l'app, pour une extension simple.
    private func splitName(_ name: String) -> (String, String) {
        let url = URL(fileURLWithPath: name)
        let pathExtension = url.pathExtension
        return pathExtension.isEmpty ? (name, "") : (url.deletingPathExtension().lastPathComponent, ".\(pathExtension)")
    }
}
