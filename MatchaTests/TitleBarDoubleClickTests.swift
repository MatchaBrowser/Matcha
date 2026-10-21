@testable import Matcha
import Testing

/// A double click at the top of the window does what System Settings asks.
struct TitleBarDoubleClickTests {
    @Test func `the choice of system settings is followed`() {
        #expect(TitleBarDoubleClick(action: "Maximize", minimizes: false) == .zoom)
        #expect(TitleBarDoubleClick(action: "Fill", minimizes: false) == .zoom)
        #expect(TitleBarDoubleClick(action: "Minimize", minimizes: false) == .minimize)
        #expect(TitleBarDoubleClick(action: "None", minimizes: true) == .nothing)
    }

    @Test func `without a choice, the window zooms, unless the old setting minimizes`() {
        #expect(TitleBarDoubleClick(action: nil, minimizes: false) == .zoom)
        #expect(TitleBarDoubleClick(action: nil, minimizes: true) == .minimize)
        // A value from a later macOS: zoom, the default.
        #expect(TitleBarDoubleClick(action: "Something New", minimizes: true) == .zoom)
    }
}
