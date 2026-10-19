import Foundation
@testable import Matcha
import Testing

/// Zoom badge next to the address pill (task 5.4): visible only outside 100%, VoiceOver announcement.
/// The click (site back to 100%) is checked with real pages in `PageZoomIntegrationTests`.
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
        // A zoom rounded by WebKit counts as 100%.
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
