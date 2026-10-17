import Foundation

/// Commandes de la barre lues dans les sélecteurs que l'éditeur de champ transmet
/// (`control(_:textView:doCommandBy:)`), après la méthode de saisie. ⌃P et ⌃N arrivent en
/// `moveUp:` et `moveDown:`.
nonisolated enum CommandBarKeyCommand: Equatable, Sendable {
    /// ↑, ⌃P, ⇧⇥.
    case moveUp
    /// ↓, ⌃N, ⇥.
    case moveDown
    /// ⏎, ⌥⏎, ⌃⏎.
    case submit
    /// ⎋.
    case cancel

    /// Nil pour un sélecteur que l'éditeur traite lui-même.
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
