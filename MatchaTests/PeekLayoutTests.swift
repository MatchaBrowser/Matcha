import CoreGraphics
import Foundation
@testable import Matcha
import Testing

struct PeekLayoutTests {
    @Test func `pane takes 85 percent and the bar sits above it`() {
        let layout = PeekLayout(container: CGSize(width: 1000, height: 800))
        #expect(layout.pane == CGRect(x: 75, y: 60, width: 850, height: 680))
        #expect(layout.toolbar == CGRect(x: 75, y: 24, width: 850, height: 28))
    }

    @Test func `a low area keeps room for the bar`() {
        let layout = PeekLayout(container: CGSize(width: 600, height: 300))
        #expect(layout.pane == CGRect(x: 45, y: 48, width: 510, height: 240))
        #expect(layout.toolbar == CGRect(x: 45, y: 12, width: 510, height: 28))
    }

    @Test func `a narrow area keeps the side margins`() {
        let layout = PeekLayout(container: CGSize(width: 100, height: 400))
        #expect(layout.pane == CGRect(x: 12, y: 48, width: 76, height: 340))
        #expect(layout.toolbar == CGRect(x: 12, y: 12, width: 76, height: 28))
    }

    @Test func `an empty area gives an empty pane`() {
        let layout = PeekLayout(container: .zero)
        #expect(layout.pane == CGRect(x: 0, y: 48, width: 0, height: 0))
        #expect(layout.toolbar == CGRect(x: 0, y: 12, width: 0, height: 28))
    }

    @Test func `opening point is a fraction from the top left`() {
        let size = CGSize(width: 100, height: 100)
        #expect(PeekLayout.fraction(of: CGPoint(x: 50, y: 25), in: size, flipped: true) == CGPoint(x: 0.5, y: 0.25))
        #expect(PeekLayout.fraction(of: CGPoint(x: 50, y: 25), in: size, flipped: false) == CGPoint(x: 0.5, y: 0.75))
        #expect(PeekLayout.fraction(of: CGPoint(x: -10, y: 500), in: size, flipped: true) == CGPoint(x: 0, y: 1))
        #expect(PeekLayout.fraction(of: CGPoint(x: 10, y: 10), in: .zero, flipped: true) == PeekLayout.center)
    }
}
