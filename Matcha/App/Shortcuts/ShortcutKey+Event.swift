import AppKit

extension ShortcutKey {
    /// Shortcut of a key press (Settings > Shortcuts); nil for a key that can't be one (a dead key, several
    /// characters). A letter keeps Shift as a modifier; another character takes the Shift that produced it (⇧= types
    /// “+”: the shortcut is ⌘+, as in the View menu).
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = Modifiers()
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
        if let special = Self.specialKey(of: event) {
            self.init(special, modifiers)
            return
        }
        guard let typed = event.charactersIgnoringModifiers, typed.count == 1, let character = typed.first,
              !character.isWhitespace, !character.isNewline
        else {
            return nil
        }
        if !character.isLetter, modifiers.contains(.shift), event.characters(byApplyingModifiers: []) != typed {
            modifiers.remove(.shift)
        }
        self.init(character, modifiers)
    }

    private static func specialKey(of event: NSEvent) -> SpecialKey? {
        // Escape and Space have no `NSEvent.SpecialKey`: their key codes (`kVK_Escape`, `kVK_Space`).
        switch event.keyCode {
        case 53: .escape
        case 49: .space
        default: event.specialKey.flatMap { specialKeys[$0] }
        }
    }

    private static let specialKeys: [NSEvent.SpecialKey: SpecialKey] = [
        .tab: .tab, .backTab: .tab, .carriageReturn: .return, .enter: .return, .newline: .return, .delete: .delete,
        .backspace: .delete, .deleteForward: .deleteForward, .upArrow: .upArrow, .downArrow: .downArrow,
        .leftArrow: .leftArrow, .rightArrow: .rightArrow, .home: .home, .end: .end, .pageUp: .pageUp, .pageDown: .pageDown,
        .f1: .function1, .f2: .function2, .f3: .function3, .f4: .function4, .f5: .function5, .f6: .function6,
        .f7: .function7, .f8: .function8, .f9: .function9, .f10: .function10, .f11: .function11, .f12: .function12,
    ]
}
