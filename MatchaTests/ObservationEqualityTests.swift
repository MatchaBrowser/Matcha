import Foundation
@testable import Matcha
import Observation
import Testing

/// Review CO8: the observed values are written without checking first; Observation itself notifies no one for the
/// same `Equatable` value. If a compiler stops doing so, this test says it.
@MainActor
@Suite(.webKit)
struct ObservationEqualityTests {
    @Test func `writing the same value notifies no one`() {
        let tab = BrowserTab(configuration: TestPages.configuration())
        let fired = SendableFlag()
        withObservationTracking {
            _ = tab.pageZoom
            _ = tab.canGoBack
        } onChange: {
            fired.raise()
        }
        tab.setPageZoom(tab.pageZoom)
        tab.updateCanGoBack()
        #expect(!fired.isRaised)
        tab.setPageZoom(tab.pageZoom + 0.25)
        #expect(fired.isRaised)
    }
}
