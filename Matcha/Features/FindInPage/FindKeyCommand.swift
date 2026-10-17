import Foundation

/// Commandes du champ de recherche lues dans les sélecteurs que l'éditeur de champ transmet
/// (`control(_:textView:doCommandBy:)`), donc après la méthode de saisie : une composition (japonais, touches
/// mortes) n'en déclenche aucune. ⇧Entrée n'a pas de sélecteur à elle : c'est `insertNewline:` avec Maj enfoncée.
nonisolated enum FindKeyCommand: Equatable, Sendable {
    /// ⏎ (et ⌥⏎, ⌃⏎) : occurrence suivante.
    case next
    /// ⇧⏎ : occurrence précédente.
    case previous
    /// ⎋ (et ⌥⎋) : ferme la barre.
    case close

    /// Nil pour un sélecteur que l'éditeur traite lui-même (⇥ change de champ, ↑ ↓ déplacent le curseur…).
    init?(selectorName: String, isShiftDown: Bool) {
        switch selectorName {
        case "insertNewline:", "insertNewlineIgnoringFieldEditor:", "insertLineBreak:":
            self = isShiftDown ? .previous : .next
        case "cancelOperation:", "complete:":
            self = .close
        default:
            return nil
        }
    }
}
