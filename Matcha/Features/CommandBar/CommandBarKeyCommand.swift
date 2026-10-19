import Foundation

/// Bar commands read from the selectors the field editor forwards (`control(_:textView:doCommandBy:)`), after the
/// input method. ⌃P and ⌃N arrive as `moveUp:` and `moveDown:`.
nonisolated enum CommandBarKeyCommand: Equatable, Sendable {
    /// ↑, ⌃P, ⇧⇥.
    case moveUp
    /// ↓, ⌃N, ⇥.
    case moveDown
    /// ⏎, ⌥⏎, ⌃⏎.
    case submit
    /// ⎋.
    case cancel

    /// Nil for a selector the editor handles itself.
    init?(selectorName: String) {
        guard let command = Self.commands[selectorName] else {
            return nil
        }
        self = command
    }

    private static let commands: [String: Self] = [
        "moveUp:": .moveUp,
        "insertBacktab:": .moveUp,
        "moveDown:": .moveDown,
        "insertTab:": .moveDown,
        "insertNewline:": .submit,
        "insertNewlineIgnoringFieldEditor:": .submit,
        "insertLineBreak:": .submit,
        "cancelOperation:": .cancel,
        "complete:": .cancel,
    ]
}
