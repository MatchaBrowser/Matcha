import Foundation
@testable import Matcha
import Testing

/// Review ON25: a resizing drag keeps its starting value until it ends, even a cancelled one.
struct ResizeDragTests {
    @Test func `the start of a drag stays the same while the value follows the pointer`() {
        var drag = ResizeDrag<Double>()
        #expect(drag.begin(at: 240) == 240)
        // The width already followed the pointer: the start stays.
        #expect(drag.begin(at: 300) == 240)
        #expect(drag.start == 240)
    }

    /// A cancelled drag (a dialog of the page during the drag) ends like the others: the next one starts from the value
    /// of that moment, without jumping.
    @Test func `after an end or a cancellation, the next drag starts from the current value`() {
        var drag = ResizeDrag<[Double]>()
        _ = drag.begin(at: [400, 400])
        drag.end()
        #expect(drag.start == nil)
        #expect(drag.begin(at: [500, 300]) == [500, 300])
        drag.end()
        drag.end()
        #expect(drag.start == nil)
    }
}
