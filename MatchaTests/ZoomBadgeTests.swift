import Foundation
@testable import Matcha
import Testing

/// Badge du zoom à côté de la pastille d'adresse (tâche 5.4) : visible hors de 100 % seulement, annonce VoiceOver.
/// Le clic (retour du site à 100 %) est vérifié avec de vraies pages dans `PageZoomIntegrationTests`.
@MainActor
struct ZoomBadgeTests {
    @Test func `the badge shows only away from 100 percent`() {
        #expect(!ZoomBadge.isShown(for: nil))
        let tab = BrowserTab(configuration: TestPages.configuration())
        #expect(!ZoomBadge.isShown(for: tab))

        tab.setPageZoom(1.15)
        #expect(ZoomBadge.isShown(for: tab))
        tab.setPageZoom(0.5)
        #expect(ZoomBadge.isShown(for: tab))
        // Un zoom arrondi par WebKit compte comme 100 %.
        tab.setPageZoom(1.0004)
        #expect(!ZoomBadge.isShown(for: tab))

        tab.setPageZoom(1.25)
        tab.unload(resettingTo: nil, title: nil)
        #expect(!ZoomBadge.isShown(for: tab))
    }

    @Test func `the announcement names the zoom`() {
        let text = ZoomAnnouncement.text(for: 1.25)
        #expect(text.hasSuffix(ZoomLevels.percentText(1.25)))
        #expect(text != ZoomLevels.percentText(1.25))
    }
}
