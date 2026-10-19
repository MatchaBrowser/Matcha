import KeyboardShortcuts

/// Global shortcut of the mini windows, configurable in Settings > General.
nonisolated enum MiniWindowShortcut {
    /// Saved name (`KeyboardShortcuts_openMiniWindow` in the defaults): never change it, the shortcut chosen by the
    /// user would be lost.
    static let storageName = "openMiniWindow"
    /// ⌥⌘N, like Little Arc: the N key (`kVK_ANSI_N`) with the Carbon modifiers `cmdKey | optionKey`.
    static let defaultCarbonKeyCode = 45
    static let defaultCarbonModifiers = 2304
    static let defaultShortcut = KeyboardShortcuts.Shortcut(carbonKeyCode: defaultCarbonKeyCode, carbonModifiers: defaultCarbonModifiers)
}

extension KeyboardShortcuts.Name {
    /// Opens a mini window from any app. The first access saves ⌥⌘N in the defaults if there is nothing there yet
    /// (KeyboardShortcuts behavior): never read by the unit tests, whose host app has the same identifier as the
    /// app.
    static let openMiniWindow = Self(MiniWindowShortcut.storageName, initial: MiniWindowShortcut.defaultShortcut)
}
