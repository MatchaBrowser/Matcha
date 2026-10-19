import Carbon.HIToolbox
@testable import Matcha
import Testing

/// Without ever touching the user's shortcut (the tests' host app has the same identifier and settings as the app).
struct MiniWindowShortcutTests {
    @Test func `the former default shortcut is option command N`() {
        #expect(MiniWindowShortcut.formerDefaultCarbonKeyCode == kVK_ANSI_N)
        #expect(MiniWindowShortcut.formerDefaultCarbonModifiers == cmdKey | optionKey)
    }

    @Test func `the stored name never changes`() {
        #expect(MiniWindowShortcut.storageName == "openMiniWindow")
    }
}
