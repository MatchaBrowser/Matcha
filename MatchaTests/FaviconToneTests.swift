import AppKit
@testable import Matcha
import Testing

struct FaviconToneTests {
    /// 10 × 10 pixel image in premultiplied RGBA: `drawn` pixels of the given color, the rest transparent.
    private func pixels(red: UInt8, green: UInt8, blue: UInt8, drawn: Int, total: Int = 100) -> [UInt8] {
        (0 ..< total).flatMap { index in index < drawn ? [red, green, blue, 255] : [0, 0, 0, 0] }
    }

    @Test func `black drawing on transparency is dark`() {
        #expect(FaviconTone.analyze(rgba: pixels(red: 20, green: 20, blue: 24, drawn: 60)) == .dark)
    }

    @Test func `white drawing on transparency is light`() {
        #expect(FaviconTone.analyze(rgba: pixels(red: 250, green: 250, blue: 250, drawn: 60)) == .light)
    }

    @Test func `colorful drawing is neutral`() {
        #expect(FaviconTone.analyze(rgba: pixels(red: 230, green: 30, blue: 30, drawn: 60)) == .neutral)
    }

    @Test func `icon with its own background is neutral`() {
        #expect(FaviconTone.analyze(rgba: pixels(red: 0, green: 0, blue: 0, drawn: 100)) == .neutral)
    }

    @Test func `empty image is neutral`() {
        #expect(FaviconTone.analyze(rgba: pixels(red: 0, green: 0, blue: 0, drawn: 0)) == .neutral)
        #expect(FaviconTone.analyze(rgba: []) == .neutral)
    }

    @MainActor
    @Test func `tone is read from a real image`() {
        let image = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 6, dy: 6)).fill()
            return true
        }
        #expect(Favicon.tone(of: image) == .dark)
    }
}
