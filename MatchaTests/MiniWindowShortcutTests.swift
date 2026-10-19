import Carbon.HIToolbox
@testable import Matcha
import Testing

/// Without ever touching `KeyboardShortcuts.Name.openMiniWindow`: its first access would write ⌥⌘N into the
/// user's settings (the tests' host app has the same identifier as the app).
struct MiniWindowShortcutTests {
    @Test func `default shortcut is option command N`() {
        #expect(MiniWindowShortcut.defaultCarbonKeyCode == kVK_ANSI_N)
        #expect(MiniWindowShortcut.defaultCarbonModifiers == cmdKey | optionKey)
    }

    @Test func `the stored name never changes`() {
        #expect(MiniWindowShortcut.storageName == "openMiniWindow")
    }
}
