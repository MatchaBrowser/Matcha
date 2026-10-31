import AppKit

/// SF Symbols as this platform knows them.
nonisolated enum SystemSymbol {
    /// True if this version of the system has the symbol `name` (`"house.fill"`).
    static func exists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}
