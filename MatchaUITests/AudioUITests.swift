import XCTest

/// Son (tâche 5.10) : un onglet en arrière-plan qui joue du son montre un haut-parleur ; un clic dessus met sa page en
/// pause sans sélectionner l'onglet ni le fermer. Page sans réseau : une musique des Souvenirs de Photos livrée avec
/// macOS, ouverte comme fichier (WebKit en fait une page qui la joue d'elle-même) ; test ignoré s'il n'y en a pas.
/// **Ce test joue quelques secondes de musique** (baisse le son) et déplace la vraie souris.
final class AudioUITests: XCTestCase {
    private static let musicDirectory = "/System/Library/Photos/Resources/FlexAudio"
    /// Valeur d'accessibilité d'un onglet qui joue du son, en français.
    private static let playing = "Lecture audio en cours"

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testSpeakerPausesABackgroundTabWithoutSelectingIt() throws {
        let music = try musicFile()
        let app = launchApp()
        XCTAssertTrue(waitForBrowserWindow(of: app))
        openAddress("file://" + music, in: app)
        let row = tabRow(titled: (music as NSString).lastPathComponent, in: app)
        XCTAssertTrue(waitForValue(of: row, timeout: 10) { $0 == Self.playing })

        // Un onglet vide passe devant : la musique continue, le haut-parleur reste.
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        XCTAssertFalse(row.isSelected)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(row.value as? String, Self.playing)

        // Le haut-parleur, juste avant la place du × (marge de 3 pt, × et haut-parleur de 26 pt) : il ne bouge pas
        // quand le × apparaît au survol.
        row.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -42, dy: 0)).click()
        XCTAssertTrue(waitUntilSilent(row, timeout: 3))
        XCTAssertFalse(row.isSelected)
        XCTAssertEqual(tabRows(in: app).count, 2)

        // En pause, pas terminée : le haut-parleur ne revient pas, ni quand on affiche l'onglet.
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(waitUntilSilent(row, timeout: 1))
        row.click()
        XCTAssertTrue(row.isSelected)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertTrue(waitUntilSilent(row, timeout: 1))
    }

    /// Premier morceau trouvé ; le test est ignoré sans lui.
    private func musicFile() throws -> String {
        let bundles = (try? FileManager.default.contentsOfDirectory(atPath: Self.musicDirectory)) ?? []
        for bundle in bundles.sorted() where bundle.hasSuffix(".smsbundle") {
            let directory = Self.musicDirectory + "/" + bundle
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            if let file = files.sorted().first(where: { $0.hasSuffix(".m4a") }) {
                return directory + "/" + file
            }
        }
        throw XCTSkip("Aucune musique de Photos dans \(Self.musicDirectory)")
    }

    /// Attend que la ligne ne dise plus « Lecture audio en cours » (sans valeur, ou vide).
    @MainActor
    private func waitUntilSilent(_ row: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { object, _ in
            ((object as? XCUIElement)?.value as? String) != Self.playing
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: row)], timeout: timeout) == .completed
    }
}
