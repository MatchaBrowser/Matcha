import Carbon.HIToolbox
@testable import Matcha
import Testing

/// Sans jamais toucher à `KeyboardShortcuts.Name.openMiniWindow` : son premier accès écrirait ⌥⌘N dans les
/// réglages de l'utilisateur (l'app hôte des tests a le même identifiant que l'app).
struct MiniWindowShortcutTests {
    @Test func `default shortcut is option command N`() {
        #expect(MiniWindowShortcut.defaultCarbonKeyCode == kVK_ANSI_N)
        #expect(MiniWindowShortcut.defaultCarbonModifiers == cmdKey | optionKey)
    }

    @Test func `the stored name never changes`() {
        #expect(MiniWindowShortcut.storageName == "openMiniWindow")
    }
}
