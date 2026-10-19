import AppKit
import KeyboardShortcuts

/// Global shortcut of the mini windows, chosen in Settings > Shortcuts; none by default (audit H5): a shortcut taken in
/// every app must be the user's choice. Inside Matcha, File > New Mini Window has its own shortcut (⌥⌘N).
nonisolated enum MiniWindowShortcut {
    /// Saved name (`KeyboardShortcuts_openMiniWindow` in the defaults): never change it, the shortcut chosen by the
    /// user would be lost.
    static let storageName = "openMiniWindow"
    /// ⌥⌘N, the global shortcut of earlier versions: the N key (`kVK_ANSI_N`) with the Carbon modifiers
    /// `cmdKey | optionKey`.
    static let formerDefaultCarbonKeyCode = 45
    static let formerDefaultCarbonModifiers = 2304
    /// Set once the former default has been removed.
    static let formerDefaultRemovedKey = "miniWindowShortcutDefaultRemoved"

    /// Earlier versions wrote ⌥⌘N at the first launch, without asking: it is removed once (a shortcut chosen by the
    /// user is kept).
    @MainActor
    static func removeFormerDefault(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: formerDefaultRemovedKey) else {
            return
        }
        defaults.set(true, forKey: formerDefaultRemovedKey)
        let former = KeyboardShortcuts.Shortcut(carbonKeyCode: formerDefaultCarbonKeyCode, carbonModifiers: formerDefaultCarbonModifiers)
        if KeyboardShortcuts.getShortcut(for: .openMiniWindow) == former {
            KeyboardShortcuts.setShortcut(nil, for: .openMiniWindow)
        }
    }

    /// The global shortcut as a menu shortcut; nil for none, or for a key that menus can't show.
    @MainActor
    static func menuKey(of shortcut: KeyboardShortcuts.Shortcut?) -> ShortcutKey? {
        // A special key (arrows, function keys) is one of AppKit's private-use characters: not compared.
        guard let shortcut, let equivalent = shortcut.nsMenuItemKeyEquivalent, equivalent.count == 1, let character = equivalent.first,
              let scalar = character.unicodeScalars.first, scalar.value > 0x20, !(0xF700 ... 0xF8FF).contains(scalar.value)
        else {
            return nil
        }
        var modifiers = ShortcutKey.Modifiers()
        let flags = shortcut.modifiers
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        return ShortcutKey(character, modifiers)
    }
}

extension KeyboardShortcuts.Name {
    /// Opens a mini window from any app; no initial shortcut (nothing is written at its first access).
    static let openMiniWindow = Self(MiniWindowShortcut.storageName)
}
