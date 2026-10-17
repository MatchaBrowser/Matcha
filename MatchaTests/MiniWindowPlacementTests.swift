import CoreGraphics
@testable import Matcha
import Testing

struct MiniWindowPlacementTests {
    /// Zone utile d'un écran de 1440 × 900 sous la barre des menus.
    private let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)

    @Test func `first mini window is centered on the screen`() {
        let frame = MiniWindowPlacement.frame(size: MiniWindowPlacement.defaultSize, in: screen, after: nil)
        #expect(frame == CGRect(x: 460, y: 123, width: 520, height: 680))
    }

    @Test func `next mini window is shifted down and right`() {
        let previous = CGRect(x: 460, y: 123, width: 520, height: 680)
        let frame = MiniWindowPlacement.frame(size: MiniWindowPlacement.defaultSize, in: screen, after: previous)
        #expect(frame == CGRect(x: 484, y: 99, width: 520, height: 680))
    }

    @Test func `a cascade leaving the screen starts again from the center`() {
        let previous = CGRect(x: 900, y: 50, width: 520, height: 680)
        let frame = MiniWindowPlacement.frame(size: MiniWindowPlacement.defaultSize, in: screen, after: previous)
        #expect(frame == CGRect(x: 460, y: 123, width: 520, height: 680))
    }

    @Test func `a previous window on another screen starts again from the center`() {
        let previous = CGRect(x: 1800, y: 200, width: 520, height: 680)
        let frame = MiniWindowPlacement.frame(size: MiniWindowPlacement.defaultSize, in: screen, after: previous)
        #expect(frame == CGRect(x: 460, y: 123, width: 520, height: 680))
    }

    @Test func `a small screen shrinks the window inside its margins`() {
        let small = CGRect(x: 0, y: 0, width: 800, height: 500)
        let frame = MiniWindowPlacement.frame(size: MiniWindowPlacement.defaultSize, in: small, after: nil)
        #expect(frame.size == CGSize(width: 520, height: 460))
        #expect(small.insetBy(dx: MiniWindowPlacement.margin, dy: MiniWindowPlacement.margin).contains(frame))
    }

    @Test func `a tiny screen keeps the minimum size at its top left`() {
        let tiny = CGRect(x: 0, y: 0, width: 300, height: 300)
        let frame = MiniWindowPlacement.frame(size: MiniWindowPlacement.defaultSize, in: tiny, after: nil)
        #expect(frame.size == MiniWindowPlacement.minimumSize)
        #expect(frame.minX == 20)
        #expect(frame.maxY == 280)
    }

    @Test func `a stored size is used when valid`() {
        let frame = MiniWindowPlacement.frame(size: CGSize(width: 600, height: 700), in: screen, after: nil)
        #expect(frame.size == CGSize(width: 600, height: 700))
    }

    @Test func `stored size is read only when valid and large enough`() {
        #expect(MiniWindowPlacement.storedSize("{600, 700}") == CGSize(width: 600, height: 700))
        #expect(MiniWindowPlacement.storedSize(nil) == nil)
        #expect(MiniWindowPlacement.storedSize("") == nil)
        #expect(MiniWindowPlacement.storedSize("grand") == nil)
        #expect(MiniWindowPlacement.storedSize("{200, 700}") == nil)
    }
}
