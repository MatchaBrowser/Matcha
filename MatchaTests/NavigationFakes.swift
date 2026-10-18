import AppKit
import Foundation
import WebKit

/// Garde les décisions passées au `decisionHandler` de WebKit.
@MainActor
final class PolicyRecorder {
    private(set) var policies: [WKNavigationActionPolicy] = []

    func record(_ policy: WKNavigationActionPolicy) {
        policies.append(policy)
    }
}

/// Clic sur un lien, avec les modificateurs et le bouton voulus (masque de WebKit : 1 gauche, 2 droit, 4 milieu,
/// 0 clic simulé par la page).
///
/// Toute propriété que le coordinateur lit doit être redéfinie ici : lire une propriété non redéfinie d'un
/// `WKNavigationAction` créé à la main fait planter le test. `targetFrame` est nil : le faux ressemble
/// toujours à un lien qui ouvre une nouvelle fenêtre. `navigationType` : `.other` pour `window.open` ou la fenêtre
/// d'un élément du menu contextuel (vérifié, tâche 5.9 : sans bouton ni touche).
@MainActor
final class FakeNavigationAction: WKNavigationAction {
    private let fakeRequest: URLRequest
    private let fakeModifierFlags: NSEvent.ModifierFlags
    private let fakeButtonNumber: Int
    private let fakeShouldPerformDownload: Bool
    private let fakeNavigationType: WKNavigationType

    init(
        url: URL,
        modifierFlags: NSEvent.ModifierFlags,
        buttonNumber: Int = 1,
        shouldPerformDownload: Bool = false,
        navigationType: WKNavigationType = .linkActivated,
    ) {
        fakeRequest = URLRequest(url: url)
        fakeModifierFlags = modifierFlags
        fakeButtonNumber = buttonNumber
        fakeShouldPerformDownload = shouldPerformDownload
        fakeNavigationType = navigationType
        super.init()
    }

    override var request: URLRequest {
        fakeRequest
    }

    override var modifierFlags: NSEvent.ModifierFlags {
        fakeModifierFlags
    }

    override var navigationType: WKNavigationType {
        fakeNavigationType
    }

    override var buttonNumber: Int {
        fakeButtonNumber
    }

    override var targetFrame: WKFrameInfo? {
        nil
    }

    override var shouldPerformDownload: Bool {
        fakeShouldPerformDownload
    }
}
