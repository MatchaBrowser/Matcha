@testable import Matcha
import Testing

struct CommandBarPlacementTests {
    @Test func `browser window keeps the 4.1 placement`() {
        #expect(CommandBarPlacement.window.top(inHeight: 1000) == 180)
        #expect(CommandBarPlacement.window.top(inHeight: 200) == 52)
        #expect(CommandBarPlacement.window.maximumWidth == 640)
        #expect(CommandBarPlacement.window.horizontalMargin == 24)
    }

    @Test func `mini window bar sits under its toolbar across the whole width`() {
        let placement = CommandBarPlacement.belowToolbar(top: 40)
        #expect(placement.top(inHeight: 680) == 40)
        #expect(placement.maximumWidth == .infinity)
        #expect(placement.horizontalMargin == 10)
        #expect(placement.bottomMargin == 10)
    }
}
