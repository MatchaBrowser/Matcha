import AppKit
import SwiftUI

/// Champ de la barre de recherche dans la page (`NSTextField`, comme la barre de commande, sans correction ni
/// remplacements) : chaque modification va à la recherche de la page, ⏎ ⇧⏎ ⎋ vont à `onCommand`. Pendant une
/// composition (japonais, touches mortes), rien n'est cherché et ces touches restent à la méthode de saisie.
struct FindTextField: NSViewRepresentable {
    let session: FindSession
    /// Page de la barre : sert à retrouver le champ qui a le clavier (`FindActions`).
    let pageID: BrowserTab.ID
    /// Texte cherché : un champ recréé (retour sur l'onglet) le reprend.
    let text: String
    /// Change à chaque ⌘F : le champ reprend le clavier et sélectionne son texte.
    let focusRequest: Int
    let onCommand: (FindKeyCommand) -> Void
    /// Le champ prend le clavier (clic) : la carte rend actif le panneau de sa page.
    var onFocus: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> CommandBarNSTextField {
        let field = CommandBarNSTextField()
        field.isBordered = false
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: NSFont.systemFontSize)
        field.cell?.usesSingleLineMode = true
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.lineBreakMode = .byClipping
        field.isAutomaticTextCompletionEnabled = false
        field.placeholderString = String(localized: FindBar.title)
        field.stringValue = text
        field.delegate = context.coordinator
        field.setAccessibilityIdentifier("findField")
        field.setAccessibilityLabel(String(localized: FindBar.title))
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.onBecomeFirstResponder = onFocus
        context.coordinator.lastFocusRequest = focusRequest
        // Seulement après ⌘F : un champ recréé en revenant sur l'onglet laisse le clavier à la page.
        field.wantsFocus = session.takeFocusRequest()
        return field
    }

    func updateNSView(_ field: CommandBarNSTextField, context: Context) {
        context.coordinator.parent = self
        field.onBecomeFirstResponder = onFocus
        // Pendant l'édition, le champ fait foi : jamais stringValue (NSControl abandonnerait l'édition).
        if field.currentEditor() == nil, field.stringValue != text {
            field.stringValue = text
        }
        if context.coordinator.lastFocusRequest != focusRequest {
            context.coordinator.lastFocusRequest = focusRequest
            if session.takeFocusRequest() {
                field.focusAndSelectAll()
            }
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView _: CommandBarNSTextField, context _: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? 200
        return CGSize(width: width, height: 18)
    }

    /// Délégué du champ ; il dit à quelle page le champ appartient.
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: FindTextField
        var lastFocusRequest = 0

        init(parent: FindTextField) {
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
            parent.session.updateQuery(field.stringValue)
        }

        func control(_: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let isShiftDown = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            // Pendant une composition, ⏎ et ⎋ appartiennent à la méthode de saisie.
            guard !textView.hasMarkedText(),
                  let command = FindKeyCommand(selectorName: NSStringFromSelector(commandSelector), isShiftDown: isShiftDown)
            else {
                return false
            }
            parent.onCommand(command)
            return true
        }
    }
}
