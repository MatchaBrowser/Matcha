import Foundation
import XCTest

/// Outils des tests des téléchargements (tâche 5.1), sans réseau : un fichier livré avec macOS que WebKit n'affiche
/// pas, ouvert depuis la barre de commande, est téléchargé.
///
/// L'app écrit dans ~/Downloads/MatchaUITests (arguments `downloadsSubfolder` et `resetDownloadsSubfolder`), jamais à
/// côté des fichiers de l'utilisateur. Le lanceur des tests est sandboxé par Xcode, en lecture seule sur tout le
/// disque : il lit le fichier et son attribut de quarantaine, mais ne peut rien effacer. C'est l'app, relancée avec
/// `resetDownloadsSubfolder`, qui efface le dossier (`removeDownloadsTestFolder`, à la fin de chaque test).
extension XCTestCase {
    static let downloadsTestFolderName = "MatchaUITests"
    /// Réglages de lancement : téléchargements dans le dossier de test, vidé au lancement.
    static let downloadsTestSettings = ["downloadsSubfolder": downloadsTestFolderName, "resetDownloadsSubfolder": "YES"]
    /// Fichiers livrés avec macOS que WebKit n'affiche pas ; le premier présent sert (les mêmes que dans
    /// `DownloadIntegrationTests`).
    static let undisplayableFiles = [
        "/usr/share/firmware/bluetooth/20702_8289.dfu",
        "/usr/share/man/man1/less.1.gz",
        "/usr/share/tokenizer/th/matrix.bin",
    ]

    /// ~/Downloads/MatchaUITests, dans le vrai dossier personnel (celui du lanceur sandboxé est son conteneur).
    var downloadsTestFolder: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Downloads").appendingPathComponent(Self.downloadsTestFolderName)
    }

    /// Fichier à télécharger ; le test est ignoré s'il n'y en a aucun.
    func undisplayableFile() throws -> String {
        guard let path = Self.undisplayableFiles.first(where: FileManager.default.isReadableFile(atPath:)) else {
            throw XCTSkip("Aucun fichier non affichable livré avec macOS")
        }
        return path
    }

    /// Ouvre `path` (fichier local) dans un nouvel onglet de `window` (l'app si nil) : il est téléchargé.
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

    /// `scope` : l'app, ou une fenêtre précise (chaque fenêtre a son panneau).
    @MainActor
    func downloadsPanel(in scope: XCUIElement) -> XCUIElement {
        scope.descendants(matching: .any).matching(identifier: "downloadsPanel").firstMatch
    }

    @MainActor
    func downloadRows(in scope: XCUIElement) -> XCUIElementQuery {
        scope.descendants(matching: .any).matching(identifier: "downloadRow")
    }

    /// Texte « Aucun téléchargement » du panneau vide.
    @MainActor
    func downloadsEmptyState(in scope: XCUIElement) -> XCUIElement {
        scope.descendants(matching: .any).matching(identifier: "downloadsEmptyState").firstMatch
    }

    /// Bouton « Afficher le dossier Téléchargements » du panneau vide ; jamais cliqué par les tests (il ouvrirait le
    /// Finder). Cherché par son identifiant seul : son style de lien peut en faire un lien pour l'accessibilité.
    @MainActor
    func downloadsShowFolderButton(in scope: XCUIElement) -> XCUIElement {
        scope.descendants(matching: .any).matching(identifier: "downloadsShowFolderButton").firstMatch
    }

    /// Présentation > « Afficher les téléchargements » / « Masquer les téléchargements » (⌥⌘L).
    @MainActor
    func toggleDownloadsWithKeyboard(in app: XCUIApplication) {
        app.typeKey("l", modifierFlags: [.command, .option])
    }

    /// Valeur de `com.apple.quarantine` (« drapeaux;date;app;événement »), nil si le fichier ne la porte pas.
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

    /// Relance l'app avec `resetDownloadsSubfolder` : elle efface le dossier de test au lancement, puis se ferme.
    @MainActor
    func removeDownloadsTestFolder() {
        let app = launchApp(settings: Self.downloadsTestSettings)
        _ = waitForBrowserWindow(of: app)
        app.terminate()
        XCTAssertFalse(FileManager.default.fileExists(atPath: downloadsTestFolder.path), "Dossier de test non effacé")
    }
}
