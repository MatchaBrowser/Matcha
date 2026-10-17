import KeyboardShortcuts

/// Raccourci global des mini-fenêtres, réglable dans Réglages > Général.
nonisolated enum MiniWindowShortcut {
    /// Nom enregistré (`KeyboardShortcuts_openMiniWindow` dans les réglages) : ne jamais le changer, le
    /// raccourci choisi par l'utilisateur serait perdu.
    static let storageName = "openMiniWindow"
    /// ⌥⌘N, comme Little Arc : touche N (`kVK_ANSI_N`) avec les modificateurs Carbon `cmdKey | optionKey`.
    static let defaultCarbonKeyCode = 45
    static let defaultCarbonModifiers = 2304
    static let defaultShortcut = KeyboardShortcuts.Shortcut(carbonKeyCode: defaultCarbonKeyCode, carbonModifiers: defaultCarbonModifiers)
}

extension KeyboardShortcuts.Name {
    /// Ouvre une mini-fenêtre depuis n'importe quelle app. Le premier accès enregistre ⌥⌘N dans les réglages
    /// s'il n'y a encore rien (comportement de KeyboardShortcuts) : jamais lu par les tests unitaires, dont
    /// l'app hôte a le même identifiant que l'app.
    static let openMiniWindow = Self(MiniWindowShortcut.storageName, initial: MiniWindowShortcut.defaultShortcut)
}
