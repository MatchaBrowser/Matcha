import AppKit
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

    /// Review ON17 and TS12: the top left corner where asked; past the top of the screens, back under it.
    @Test func `a placed window has its top left corner at the point, kept on the screen`() throws {
        let screen = try #require(NSScreen.main)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: true,
        )
        let corner = CGPoint(x: screen.visibleFrame.minX + 100, y: screen.visibleFrame.maxY - 100)
        BrowserWindowFrame.place(window, topLeft: corner)
        #expect(window.frame.minX == corner.x)
        #expect(window.frame.maxY == corner.y)

        // Past the top of the screen: on the nearest one (another screen may be above), under its top.
        let far = CGPoint(x: corner.x, y: screen.frame.maxY + 500)
        BrowserWindowFrame.place(window, topLeft: far)
        let screens = NSScreen.screens
        let nearest = try #require(BrowserWindowFrame.screenIndex(of: far, in: screens.map(\.frame)).map { screens[$0] })
        #expect(nearest.frame.intersects(window.frame))
        #expect(window.frame.maxY <= nearest.frame.maxY)
    }

    /// Review TS12: a new window opens just below and to the right of the front one, at its size; only the windows of
    /// the browser group count.
    @Test func `a cascaded window opens below and to the right of the front one`() {
        let front = CGRect(x: 100, y: 300, width: 1200, height: 800)
        let cascaded = BrowserWindowFrame.cascadedFrame(from: front)
        #expect(cascaded.size == front.size)
        // 24 pt to the right, 24 pt lower (y goes up on screen).
        #expect(cascaded.origin == CGPoint(x: 124, y: 276))

        let window = NSWindow(contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true)
        window.identifier = NSUserInterfaceItemIdentifier("\(MatchaApp.browserWindowID)-AppWindow-1")
        #expect(BrowserWindowFrame.isBrowserWindow(window))
        window.identifier = NSUserInterfaceItemIdentifier("com_apple_SwiftUI_Settings_window")
        #expect(!BrowserWindowFrame.isBrowserWindow(window))
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
