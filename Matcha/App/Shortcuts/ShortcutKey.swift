import SwiftUI

/// A menu shortcut (Settings > Shortcuts): a key as the keyboard layout types it (“t”, “+”, “[”), or a special key,
/// and its modifiers. Kept as characters, like SwiftUI's shortcuts, never as key positions: ⌘W stays ⌘W on an AZERTY
/// keyboard. Saved as text (`storageValue`). Pure type.
nonisolated struct ShortcutKey: Hashable, Sendable {
    enum Key: Hashable, Sendable {
        /// A lowercase letter, a digit or a punctuation mark.
        case character(Character)
        case special(SpecialKey)
    }

    enum SpecialKey: String, CaseIterable, Sendable {
        case tab, `return`, escape, delete, deleteForward, space
        case upArrow, downArrow, leftArrow, rightArrow, home, end, pageUp, pageDown
        case function1 = "f1", function2 = "f2", function3 = "f3", function4 = "f4", function5 = "f5", function6 = "f6"
        case function7 = "f7", function8 = "f8", function9 = "f9", function10 = "f10", function11 = "f11", function12 = "f12"

        /// F1 to F12: usable without ⌘ or ⌃.
        var isFunctionKey: Bool {
            functionKeyNumber != nil
        }

        var functionKeyNumber: Int? {
            guard rawValue.hasPrefix("f"), let number = Int(rawValue.dropFirst()) else {
                return nil
            }
            return number
        }
    }

    struct Modifiers: OptionSet, Hashable, Sendable {
        let rawValue: Int

        static let control = Self(rawValue: 1 << 0)
        static let option = Self(rawValue: 1 << 1)
        static let shift = Self(rawValue: 1 << 2)
        static let command = Self(rawValue: 1 << 3)
    }

    let key: Key
    let modifiers: Modifiers

    /// A letter is kept in lowercase: Shift is a modifier of its own.
    init(_ character: Character, _ modifiers: Modifiers = .command) {
        key = .character(Character(character.lowercased()))
        self.modifiers = modifiers
    }

    init(_ special: SpecialKey, _ modifiers: Modifiers = .command) {
        key = .special(special)
        self.modifiers = modifiers
    }

    /// Usable in a menu: with ⌘ or ⌃ (a shortcut with only ⌥ or ⇧ would take a character from typing), or a function
    /// key.
    var isUsableInMenus: Bool {
        if case let .special(special) = key, special.isFunctionKey {
            return true
        }
        return !modifiers.isDisjoint(with: [.command, .control])
    }

    // MARK: Text

    /// As the menus show it: “⌃⌥⇧⌘T”, “⌘[”, “⌥⌘↩”.
    var displayText: String {
        var text = ""
        if modifiers.contains(.control) {
            text += "⌃"
        }
        if modifiers.contains(.option) {
            text += "⌥"
        }
        if modifiers.contains(.shift) {
            text += "⇧"
        }
        if modifiers.contains(.command) {
            text += "⌘"
        }
        switch key {
        case let .character(character):
            text += character.uppercased()
        case let .special(special):
            text += Self.symbol(of: special)
        }
        return text
    }

    private static func symbol(of special: SpecialKey) -> String {
        symbols[special] ?? special.rawValue.uppercased()
    }

    private static let symbols: [SpecialKey: String] = [
        .tab: "⇥", .return: "↩", .escape: "⎋", .delete: "⌫", .deleteForward: "⌦", .space: "␣", .upArrow: "↑",
        .downArrow: "↓", .leftArrow: "←", .rightArrow: "→", .home: "↖", .end: "↘", .pageUp: "⇞", .pageDown: "⇟",
    ]

    /// Saved form: the modifiers as in macOS's own key equivalents (`^` ⌃, `~` ⌥, `$` ⇧, `@` ⌘), then the character
    /// or `{name}` of the special key. “@$t” is ⇧⌘T.
    var storageValue: String {
        var text = ""
        for (modifier, symbol) in Self.storageSymbols where modifiers.contains(modifier) {
            text.append(symbol)
        }
        switch key {
        case let .character(character):
            text.append(character)
        case let .special(special):
            text += "{\(special.rawValue)}"
        }
        return text
    }

    /// Reads `storageValue`; nil for anything else.
    init?(storageValue: String) {
        var rest = Substring(storageValue)
        let key: Key
        if rest.hasSuffix("}"), let open = rest.lastIndex(of: "{") {
            guard let special = SpecialKey(rawValue: String(rest[rest.index(after: open) ..< rest.index(before: rest.endIndex)])) else {
                return nil
            }
            key = .special(special)
            rest = rest[..<open]
        } else if let last = rest.last {
            key = .character(last)
            rest = rest.dropLast()
        } else {
            return nil
        }
        var modifiers = Modifiers()
        for symbol in rest {
            guard let modifier = Self.storageSymbols.first(where: { $0.1 == symbol })?.0, !modifiers.contains(modifier) else {
                return nil
            }
            modifiers.insert(modifier)
        }
        if case let .character(character) = key, character.lowercased() != String(character) {
            return nil
        }
        self.key = key
        self.modifiers = modifiers
    }

    private static let storageSymbols: [(Modifiers, Character)] = [(.control, "^"), (.option, "~"), (.shift, "$"), (.command, "@")]

    // MARK: SwiftUI

    var keyboardShortcut: KeyboardShortcut {
        KeyboardShortcut(keyEquivalent, modifiers: eventModifiers)
    }

    private var eventModifiers: EventModifiers {
        var result = EventModifiers()
        if modifiers.contains(.control) {
            result.insert(.control)
        }
        if modifiers.contains(.option) {
            result.insert(.option)
        }
        if modifiers.contains(.shift) {
            result.insert(.shift)
        }
        if modifiers.contains(.command) {
            result.insert(.command)
        }
        return result
    }

    private var keyEquivalent: KeyEquivalent {
        switch key {
        case let .character(character):
            KeyEquivalent(character)
        case let .special(special):
            Self.keyEquivalent(of: special)
        }
    }

    private static func keyEquivalent(of special: SpecialKey) -> KeyEquivalent {
        if let number = special.functionKeyNumber, let scalar = Unicode.Scalar(0xF703 + number) {
            // AppKit's function keys: F1 is U+F704 (`NSF1FunctionKey`), then one after the other.
            return KeyEquivalent(Character(scalar))
        }
        return keyEquivalents[special] ?? .space
    }

    private static let keyEquivalents: [SpecialKey: KeyEquivalent] = [
        .tab: .tab, .return: .return, .escape: .escape, .delete: .delete, .deleteForward: .deleteForward, .space: .space,
        .upArrow: .upArrow, .downArrow: .downArrow, .leftArrow: .leftArrow, .rightArrow: .rightArrow, .home: .home,
        .end: .end, .pageUp: .pageUp, .pageDown: .pageDown,
    ]
}
