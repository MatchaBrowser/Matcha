import AppKit
import SwiftUI

/// Command bar input field (`NSTextField`): the text comes from the model, each change and each keyboard command
/// (↑ ↓ ⏎ ⎋) is sent back to it. Commands go through `control(_:textView:doCommandBy:)`, so after the input method:
/// a composition (Japanese, dead keys) is never interrupted.
struct CommandBarTextField: NSViewRepresentable {
    let text: String
    /// Changes on each open request: the field takes the keyboard back and selects all.
    let focusRequest: Int
    let onTextChange: (String) -> Void
    let onKey: (CommandBarKeyCommand) -> Void
    /// The field stopped being edited (click elsewhere, another field…).
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
            // During editing, never stringValue (NSControl would abandon editing), nor during a composition.
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

    /// Replaces the text being edited (mode change, bar reopened) through the text system, so that undo (⌘Z) knows
    /// about it: a plain assignment of `string` would leave typing undos on old ranges, and ⌘Z would overflow the
    /// text. The `controlTextDidChange` that follows sends the model back the text it already has.
    private static func replaceText(of editor: NSTextView, with text: String) {
        let range = NSRange(location: 0, length: (editor.string as NSString).length)
        guard editor.shouldChangeText(in: range, replacementString: text) else {
            // Non-editable field (should not happen): text forced, undos forgotten.
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
            // Composition in progress (dead key, input method): the text is not typed yet.
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {
                return
            }
            parent.onTextChange(field.stringValue)
        }

        func control(_: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // During a composition, ↑ ↓ ⏎ ⎋ belong to the input method.
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
