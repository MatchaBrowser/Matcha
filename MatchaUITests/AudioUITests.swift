import XCTest

/// Sound (task 5.10): a background tab that plays sound shows a speaker; clicking it pauses its page without
/// selecting or closing the tab. Page without network: a Photos Memories track shipped with macOS, opened as a file
/// (WebKit turns it into a page that plays it by itself); test skipped if there is none.
/// **This test plays a few seconds of music** (turn the volume down) and moves the real mouse.
final class AudioUITests: XCTestCase {
    private static let musicDirectory = "/System/Library/Photos/Resources/FlexAudio"
    /// Accessibility value of a tab that plays sound, in French.
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

        // An empty tab comes to the front: the music keeps playing, the speaker stays.
        openEmptyTab(in: app)
        XCTAssertTrue(waitForCount(tabRows(in: app), 2))
        XCTAssertFalse(row.isSelected)
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(row.value as? String, Self.playing)

        // The speaker, just before the spot of the × (3 pt margin, 26 pt × and speaker): it doesn't move when the ×
        // appears on hover.
        row.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5)).withOffset(CGVector(dx: -42, dy: 0)).click()
        XCTAssertTrue(waitUntilSilent(row, timeout: 3))
        XCTAssertFalse(row.isSelected)
        XCTAssertEqual(tabRows(in: app).count, 2)

        // Paused, not finished: the speaker doesn't come back, not even when the tab is shown. Direct read: a predicate
        // wait only checks after about one second, never with a one-second delay.
        Thread.sleep(forTimeInterval: 3)
        XCTAssertNotEqual(row.value as? String, Self.playing)
        row.click()
        XCTAssertTrue(row.isSelected)
        Thread.sleep(forTimeInterval: 3)
        XCTAssertNotEqual(row.value as? String, Self.playing)
    }

    /// First track found; the test is skipped without it.
    private func musicFile() throws -> String {
        let bundles = (try? FileManager.default.contentsOfDirectory(atPath: Self.musicDirectory)) ?? []
        for bundle in bundles.sorted() where bundle.hasSuffix(".smsbundle") {
            let directory = Self.musicDirectory + "/" + bundle
            let files = (try? FileManager.default.contentsOfDirectory(atPath: directory)) ?? []
            if let file = files.sorted().first(where: { $0.hasSuffix(".m4a") }) {
                return directory + "/" + file
            }
        }
        try requireResource(false, "No Photos music in \(Self.musicDirectory)")
        return ""
    }

    /// Waits until the row no longer says “Playing Audio” (no value, or empty).
    @MainActor
    private func waitUntilSilent(_ row: XCUIElement, timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate { object, _ in
            ((object as? XCUIElement)?.value as? String) != Self.playing
        }
        return XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: row)], timeout: timeout) == .completed
    }
}
