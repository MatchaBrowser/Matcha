import Foundation
@testable import Matcha
import WebKit

/// Taille demandée par une page (`window.open(url, nom, "width=…,height=…")`), comme WebKit la transmet au délégué.
/// Seules les propriétés lues par l'app sont redéfinies.
@MainActor
final class FakeWindowFeatures: WKWindowFeatures {
    private let fakeWidth: NSNumber?
    private let fakeHeight: NSNumber?

    init(width: Double? = nil, height: Double? = nil) {
        fakeWidth = width.map { NSNumber(value: $0) }
        fakeHeight = height.map { NSNumber(value: $0) }
        super.init()
    }

    override var width: NSNumber? {
        fakeWidth
    }

    override var height: NSNumber? {
        fakeHeight
    }
}

extension PopupWindowManager {
    /// Zone utile de l'écran des tests.
    static let testScreen = CGRect(x: 0, y: 25, width: 1440, height: 875)

    /// Gestionnaire de test : rien de retenu, aucune fenêtre à l'écran.
    static func forTests(isPrivate: Bool = false) -> PopupWindowManager {
        let manager = PopupWindowManager(
            faviconService: FaviconService(directory: nil),
            downloadScope: .regular,
            siteZooms: nil,
            isPrivate: isPrivate,
        )
        manager.prepareForTests()
        return manager
    }

    /// Aucune fenêtre à l'écran, et toujours le même écran.
    func prepareForTests() {
        present = { _ in }
        visibleScreenFrame = { _ in Self.testScreen }
    }
}

extension WKWebView {
    /// `window.open(url, '_blank', features)` dans la page ; compté comme un geste de l'utilisateur par WebKit.
    func openWindow(_ url: URL, features: String) async throws {
        _ = try await evaluateJavaScript("window.open('\(url.absoluteString)', '_blank', '\(features)'); true")
    }

    /// Vrai si la page a encore la page qui l'a ouverte (`window.opener`).
    func hasOpener() async throws -> Bool {
        try await evaluateJavaScript("window.opener !== null") as? Bool == true
    }
}
