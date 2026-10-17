import AppKit
import SwiftUI

/// Champ de saisie de la barre de commande (`NSTextField`) : le texte vient du modèle, chaque
/// modification et chaque commande clavier (↑ ↓ ⏎ ⎋) lui est renvoyée. Les commandes passent par
/// `control(_:textView:doCommandBy:)`, donc après la méthode de saisie : une composition (japonais,
/// touches mortes) n'est jamais interrompue.
struct CommandBarTextField: NSViewRepresentable {
    let text: String
    /// Change à chaque demande d'ouverture : le champ reprend le clavier et sélectionne tout.
    let focusRequest: Int
    let onTextChange: (String) -> Void
    let onKey: (CommandBarKeyCommand) -> Void
    /// Le champ a cessé d'être édité (clic ailleurs, autre champ…).
    let onEditingEnded: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CommandBarNSTextField {
        let field = CommandBarNSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 18)
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.lineBreakMode = .byClipping
        field.isAutomaticTextCompletionEnabled = false
        field.placeholderString = String(localized: "Search or enter address")
        field.stringValue = text
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("addressField")
        field.setAccessibilityLabel(String(localized: "Search or enter address"))
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.wantsFocus = true
        context.coordinator.lastFocusRequest = focusRequest
        return field
    }

    func updateNSView(_ field: CommandBarNSTextField, context: Context) {
        context.coordinator.parent = self
        if let editor = field.currentEditor() as? NSTextView {
            // Pendant l'édition, jamais stringValue (NSControl abandonnerait l'édition) ni pendant une composition.
            if !editor.hasMarkedText(), editor.string != text {
                Self.replaceText(of: editor, with: text)
            }
        } else if field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            field.focusAndSelectAll()
        }
    }

    /// Remplace le texte en cours d'édition (changement de mode, barre rouverte) par le système de
    /// texte, pour que l'annulation (⌘Z) le connaisse : une simple affectation de `string` laisserait
    /// les annulations de frappe sur d'anciennes plages, et ⌘Z déborderait du texte. Le
    /// `controlTextDidChange` qui suit renvoie au modèle le texte qu'il a déjà.
    private static func replaceText(of editor: NSTextView, with text: String) {
        let range = NSRange(location: 0, length: (editor.string as NSString).length)
        guard editor.shouldChangeText(in: range, replacementString: text) else {
            // Champ non modifiable (ne devrait pas arriver) : texte forcé, annulations oubliées.
            editor.string = text
            editor.undoManager?.removeAllActions()
            return
        }
        editor.replaceCharacters(in: range, with: text)
        editor.didChangeText()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView _: CommandBarNSTextField, context _: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 400, height: 24)
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CommandBarTextField
        var lastFocusRequest = 0

        init(parent: CommandBarTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else {
                return
            }
            // Composition en cours (touche morte, méthode de saisie) : le texte n'est pas encore tapé.
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {
                return
            }
            parent.onTextChange(field.stringValue)
        }

        func control(_: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // Pendant une composition, ↑ ↓ ⏎ ⎋ appartiennent à la méthode de saisie.
            guard !textView.hasMarkedText(),
                  let command = CommandBarKeyCommand(selectorName: NSStringFromSelector(commandSelector))
            else {
                return false
            }
            parent.onKey(command)
            return true
        }

        func controlTextDidEndEditing(_: Notification) {
            parent.onEditingEnded()
        }
    }
}
