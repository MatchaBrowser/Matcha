@testable import Matcha
import Testing

struct SidebarMetricsTests {
    @Test(arguments: [(100.0, 180.0), (180.0, 180.0), (250.0, 250.0), (400.0, 400.0), (900.0, 400.0)])
    func `width is clamped between 180 and 400`(width: Double, expected: Double) {
        #expect(SidebarMetrics.clampedWidth(width) == expected)
    }
}
