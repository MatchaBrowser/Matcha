import AppKit
import Foundation
@testable import Matcha
import Testing

/// Zoom levels (task 5.4): Safari's, next and previous step from any zoom, bounds, displayed text, and ⌘= read as ⌘+.
struct ZoomLevelsTests {
    @Test func `the steps are Safari's`() {
        #expect(ZoomLevels.steps == [0.5, 0.75, 0.85, 1, 1.15, 1.25, 1.5, 1.75, 2, 2.5, 3])
        #expect(ZoomLevels.minimum == 0.5)
        #expect(ZoomLevels.maximum == 3)
    }

    @Test(arguments: [(1.0, 1.15), (0.5, 0.75), (0.85, 1.0), (2.5, 3.0), (1.1, 1.15), (0.2, 0.5), (1.15 - 0.0001, 1.25)])
    func `zoom in goes to the next step`(current: Double, expected: Double) {
        #expect(ZoomLevels.step(after: current) == expected)
        #expect(ZoomLevels.Change.zoomIn.level(from: current) == expected)
    }

    @Test(arguments: [(1.0, 0.85), (0.75, 0.5), (3.0, 2.5), (1.1, 1.0), (5.0, 3.0), (1.15 + 0.0001, 1.0)])
    func `zoom out goes to the previous step`(current: Double, expected: Double) {
        #expect(ZoomLevels.step(before: current) == expected)
        #expect(ZoomLevels.Change.zoomOut.level(from: current) == expected)
    }

    @Test func `nothing beyond the bounds`() {
        #expect(ZoomLevels.step(after: 3) == nil)
        #expect(ZoomLevels.step(after: 4) == nil)
        #expect(ZoomLevels.step(before: 0.5) == nil)
        #expect(ZoomLevels.step(before: 0.3) == nil)
    }

    @Test func `actual size only changes another zoom`() {
        #expect(ZoomLevels.Change.actualSize.level(from: 1.25) == 1)
        #expect(ZoomLevels.Change.actualSize.level(from: 0.5) == 1)
        #expect(ZoomLevels.Change.actualSize.level(from: 1) == nil)
        #expect(ZoomLevels.Change.actualSize.level(from: 1.0004) == nil)
    }

    @Test func `clamping keeps the zoom between 50 and 300 percent`() {
        #expect(ZoomLevels.clamped(0.1) == 0.5)
        #expect(ZoomLevels.clamped(7) == 3)
        #expect(ZoomLevels.clamped(1.3) == 1.3)
        #expect(ZoomLevels.clamped(.nan) == 1)
        #expect(ZoomLevels.clamped(.infinity) == 1)
    }

    @Test func `percent text follows the language`() {
        #expect(ZoomLevels.percentText(1.15, locale: Locale(identifier: "en_US")) == "115%")
        // Narrow no-break space (U+202F) or no-break space (U+00A0) depending on the ICU version: only the digits and
        // “%” count.
        let french = ZoomLevels.percentText(0.85, locale: Locale(identifier: "fr_FR"))
        #expect(french.hasPrefix("85"))
        #expect(french.hasSuffix("%"))
        #expect(french.unicodeScalars.count == 4)
        #expect(ZoomLevels.percentText(2.5, locale: Locale(identifier: "en_US")) == "250%")
    }

    @Test func `command equals is zoom in, with or without shift`() {
        #expect(ZoomKeyAlias.isZoomIn(charactersIgnoringModifiers: "=", modifierFlags: .command))
        #expect(ZoomKeyAlias.isZoomIn(charactersIgnoringModifiers: "=", modifierFlags: [.command, .shift]))
        #expect(ZoomKeyAlias.isZoomIn(charactersIgnoringModifiers: "=", modifierFlags: [.command, .capsLock]))
        #expect(!ZoomKeyAlias.isZoomIn(charactersIgnoringModifiers: "=", modifierFlags: []))
        #expect(!ZoomKeyAlias.isZoomIn(charactersIgnoringModifiers: "=", modifierFlags: [.command, .option]))
        #expect(!ZoomKeyAlias.isZoomIn(charactersIgnoringModifiers: "=", modifierFlags: [.command, .control]))
        #expect(!ZoomKeyAlias.isZoomIn(charactersIgnoringModifiers: "+", modifierFlags: .command))
        #expect(!ZoomKeyAlias.isZoomIn(charactersIgnoringModifiers: nil, modifierFlags: .command))
    }

    @MainActor
    @Test func `command equals becomes command plus for the menu`() throws {
        let event = try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "=",
            charactersIgnoringModifiers: "=",
            isARepeat: false,
            keyCode: 24,
        ))
        let zoomIn = try #require(ZoomKeyAlias.zoomInEvent(for: event))
        #expect(zoomIn.charactersIgnoringModifiers == "+")
        #expect(zoomIn.modifierFlags.contains(.command))
        #expect(zoomIn.keyCode == 24)

        // A real menu recognizes it as “Zoom In” (⌘+), and does not recognize ⌘=.
        final class Target: NSObject {
            var count = 0
            @objc func zoomIn(_: Any?) {
                count += 1
            }
        }
        let target = Target()
        let menu = NSMenu()
        let item = NSMenuItem(title: "Zoom In", action: #selector(Target.zoomIn(_:)), keyEquivalent: "+")
        item.target = target
        menu.addItem(item)
        #expect(!menu.performKeyEquivalent(with: event))
        #expect(menu.performKeyEquivalent(with: zoomIn))
        #expect(target.count == 1)
    }
}
