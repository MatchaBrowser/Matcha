import Foundation
@testable import Matcha
import WebKit

/// Fake main window: it counts the times it is brought to the front.
@MainActor
final class FakeMainWindowLink: MainWindowLink {
    let windowModel: WindowModel?
    var isShown: Bool
    private(set) var broughtToFront = 0

    init(windowModel: WindowModel, isShown: Bool = true) {
        self.windowModel = windowModel
        self.isShown = isShown
    }

    func bringToFront() {
        broughtToFront += 1
    }
}

extension MiniWindowManager {
    /// Test manager: nothing remembered, local `obtest:` pages, no panel on screen, no global shortcut (`start()`
    /// is never called), suggestions turned off.
    static func forTests(session: BrowserSession) -> MiniWindowManager {
        let manager = MiniWindowManager(session: session, defaults: nil)
        manager.makeConfiguration = { _ in TestPages.configuration() }
        manager.present = { _ in }
        manager.visibleScreenFrame = { CGRect(x: 0, y: 25, width: 1440, height: 875) }
        manager.commandBarSettings = {
            CommandBarSettings(searchEngine: .google, newTabPage: .blank, homePage: "", showsSearchSuggestions: false)
        }
        return manager
    }
}

extension BrowserSession {
    /// True if no Space has a tab (a mini window adds none).
    var hasNoTabs: Bool {
        spaces.allSatisfy(\.tabManager.tabs.isEmpty)
    }
}

/// Two frames equal to within half a point: AppKit aligns windows on pixels.
func roughlyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    abs(lhs.minX - rhs.minX) <= 0.5 && abs(lhs.minY - rhs.minY) <= 0.5
        && abs(lhs.width - rhs.width) <= 0.5 && abs(lhs.height - rhs.height) <= 0.5
}
