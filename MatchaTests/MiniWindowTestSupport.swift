import Foundation
@testable import Matcha
import WebKit

/// Fenêtre principale factice : elle compte les mises au premier plan.
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
    /// Gestionnaire de test : rien de retenu, pages locales `obtest:`, aucun panneau à l'écran, aucun raccourci
    /// global (`start()` n'est jamais appelé), suggestions coupées.
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
    /// Vrai si aucun Space n'a d'onglet (une mini-fenêtre n'en ajoute aucun).
    var hasNoTabs: Bool {
        spaces.allSatisfy(\.tabManager.tabs.isEmpty)
    }
}

/// Deux cadres égaux au demi-point près : AppKit aligne les fenêtres sur les pixels.
func roughlyEqual(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
    abs(lhs.minX - rhs.minX) <= 0.5 && abs(lhs.minY - rhs.minY) <= 0.5
        && abs(lhs.width - rhs.width) <= 0.5 && abs(lhs.height - rhs.height) <= 0.5
}
