import XCTest

/// Téléchargements (tâche 5.1) : bouton du pied de la barre, liste, vrai fichier en quarantaine, fenêtre privée, barre
/// masquée. Sans réseau ; fichiers écrits dans ~/Downloads/MatchaUITests puis effacés (voir `UITestSupport+Downloads`).
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
        XCTAssertFalse(button.exists)

        download(source, in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 10))
        // Rien ne s'ouvre de soi-même : ni la liste, ni le fichier.
        XCTAssertFalse(downloadsPopover(in: app).waitForExistence(timeout: 1))

        button.click()
        XCTAssertTrue(downloadsPopover(in: app).waitForExistence(timeout: 3))
        let row = downloadRows(in: app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))
        XCTAssertEqual(downloadRows(in: app).count, 1)
        XCTAssertEqual(row.label, name)
        // Terminé : « Afficher dans le Finder » remplace « Annuler ».
        XCTAssertTrue(row.buttons["downloadShowInFinderButton"].waitForExistence(timeout: 20))
        XCTAssertFalse(row.buttons["downloadCancelButton"].exists)

        // Hors de l'app : le vrai fichier, complet, en quarantaine au nom de Matcha.
        let file = downloadsTestFolder.appendingPathComponent(name)
        let size = try FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int
        XCTAssertEqual(size, try FileManager.default.attributesOfItem(atPath: source)[.size] as? Int)
        let quarantine = try XCTUnwrap(quarantineAttribute(of: file), "Fichier sans attribut de quarantaine")
        XCTAssertTrue(quarantine.contains(";Matcha;"), quarantine)

        // « Effacer » vide la liste sans toucher au fichier : la liste se ferme, le bouton disparaît.
        let clear = app.buttons["downloadsClearButton"]
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        clear.click()
        XCTAssertTrue(button.waitForNonExistence(timeout: 3))
        XCTAssertFalse(downloadsPopover(in: app).exists)
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
        XCTAssertTrue(downloadsButton(in: app).waitForExistence(timeout: 10))
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
    /// reste dans le dossier (l'oubli de la liste est vérifié par `DownloadManagerTests`).
    @MainActor
    func testPrivateWindowHasItsOwnDownloadsList() throws {
        let source = try undisplayableFile()
        let app = launchForDownloads()
        let privateWindow = openPrivateWindow(in: app)

        download(source, in: app, window: privateWindow)
        XCTAssertTrue(downloadsButton(in: privateWindow).waitForExistence(timeout: 10))
        // La fenêtre principale ne montre pas les téléchargements privés.
        XCTAssertEqual(app.buttons.matching(identifier: "downloadsButton").count, 1)
        let file = downloadsTestFolder.appendingPathComponent(URL(fileURLWithPath: source).lastPathComponent)
        XCTAssertTrue(waitForFile(file))

        app.typeKey("w", modifierFlags: [.command, .shift])
        XCTAssertTrue(privateWindow.waitForNonExistence(timeout: 5))
        XCTAssertFalse(downloadsButton(in: app).exists)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        // Une nouvelle fenêtre privée repart sans liste.
        let newPrivateWindow = openPrivateWindow(in: app)
        XCTAssertFalse(downloadsButton(in: newPrivateWindow).waitForExistence(timeout: 1))
        app.terminate()
    }

    /// Barre masquée (⌘S) : la liste ouverte depuis la barre apparue au survol reste ouverte quand le pointeur y va.
    @MainActor
    func testDownloadsListStaysOpenOverTheHiddenSidebar() throws {
        let source = try undisplayableFile()
        let app = launchForDownloads()
        let window = app.windows.firstMatch
        download(source, in: app)
        let button = downloadsButton(in: app)
        XCTAssertTrue(button.waitForExistence(timeout: 10))

        moveAwayFromLeftEdge(in: window)
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(button.waitForNonExistence(timeout: 3))
        window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 3, dy: 0)).hover()
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.click()
        let row = downloadRows(in: app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3))

        row.hover()
        sleep(1)
        XCTAssertTrue(row.exists)
        XCTAssertTrue(button.exists)
        // Un clic sur la page ferme la liste ; loin du bord, la barre se masque à nouveau.
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).click()
        XCTAssertTrue(row.waitForNonExistence(timeout: 3))
        XCTAssertTrue(button.waitForNonExistence(timeout: 3))
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
