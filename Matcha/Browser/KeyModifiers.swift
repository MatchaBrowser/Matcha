/// Keys held during a click on a link, as the navigation rules read them (`NavigationPolicy`): only the four that change
/// where a link opens. Caps Lock, Fn or the numeric keypad change nothing. Each platform makes them from its own events
/// (`KeyModifiers+AppKit`), so that the rules never depend on the UI.
nonisolated struct KeyModifiers: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let shift = KeyModifiers(rawValue: 1 << 0)
    static let control = KeyModifiers(rawValue: 1 << 1)
    static let option = KeyModifiers(rawValue: 1 << 2)
    static let command = KeyModifiers(rawValue: 1 << 3)
}
