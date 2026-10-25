import CoreGraphics
import Foundation
@testable import Matcha
import Testing

/// Where windows and drop zones go: screen of a detached window, pointer after a drag out, split drop zone.
@MainActor
struct WindowLayoutTests {
    /// A laptop under an external screen placed above it.
    private let screens = [CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: -200, y: 982, width: 2560, height: 1440)]

    /// Review ON17: the screen of the drop, not the one SwiftUI opened the window on.
    @Test func `a detached window goes to the screen of the drop`() {
        #expect(BrowserWindowFrame.screenIndex(of: CGPoint(x: 800, y: 1500), in: screens) == 1)
        #expect(BrowserWindowFrame.screenIndex(of: CGPoint(x: 800, y: 400), in: screens) == 0)
        // Between screens or just off one: the nearest.
        #expect(BrowserWindowFrame.screenIndex(of: CGPoint(x: 3000, y: 1200), in: screens) == 1)
        #expect(BrowserWindowFrame.screenIndex(of: CGPoint(x: 10, y: 10), in: []) == nil)
    }

    /// Review ON21: the pointer lands in the new window's sidebar, under the band of the window buttons.
    @Test func `after a drag out, the pointer lands under the window buttons`() {
        let point = CGPoint(x: 900, y: 700)
        let origin = TabDragOutModifier.windowOrigin(forDropAt: point)
        #expect(origin.y - point.y > SidebarTopBar.height)
        #expect(point.x - origin.x < SidebarMetrics.clampedWidth(0))
    }

    /// Review ON22: in the mode with a column of icons, the card starts after the column.
    @Test func `the split drop zone starts after the floating sidebar`() {
        #expect(BrowserWindowView.splitDropInset(floatingWidth: nil, showsCompactSidebar: true) == 0)
        #expect(BrowserWindowView.splitDropInset(floatingWidth: 260, showsCompactSidebar: false) == 260 - BrowserWindowView.cardMargin)
        #expect(BrowserWindowView.splitDropInset(floatingWidth: 260, showsCompactSidebar: true) == 260 - CompactSidebar.width)
    }
}
