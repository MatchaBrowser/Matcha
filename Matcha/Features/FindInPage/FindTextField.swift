import AppKit
import SwiftUI

/// Field of the find-in-page bar (`NSTextField`, like the command bar, without correction or replacements): each
/// change goes to the page's search, ⏎ ⇧⏎ ⎋ go to `onCommand`. During a composition (Japanese, dead keys), nothing
/// is searched and these keys stay with the input method.
struct FindTextField: NSViewRepresentable {
    let session: FindSession
    /// Page of the bar: used to find the field that has keyboard focus (`FindActions`).
    let pageID: BrowserTab.ID
    /// Searched text: a recreated field (back on the tab) picks it up again.
    let text: String
    /// Changes at each ⌘F: the field takes keyboard focus again and selects its text.
    let focusRequest: Int
    let onCommand: (FindKeyCommand) -> Void
    /// The field takes keyboard focus (click): the card makes its page's pane active.
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
        // Only after ⌘F: a field recreated when coming back to the tab leaves keyboard focus to the page.
        field.wantsFocus = session.takeFocusRequest()
        return field
    }

    func updateNSView(_ field: CommandBarNSTextField, context: Context) {
        context.coordinator.parent = self
        field.onBecomeFirstResponder = onFocus
        // During editing, the field is authoritative: never stringValue (NSControl would abandon editing).
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

    /// Delegate of the field; it tells which page the field belongs to.
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
            // Composition in progress (dead key, input method): the text is not typed yet.
            if let editor = field.currentEditor() as? NSTextView, editor.hasMarkedText() {
                return
            }
            parent.session.updateQuery(field.stringValue)
        }

        func control(_: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            let isShiftDown = NSApp.currentEvent?.modifierFlags.contains(.shift) == true
            // During a composition, ⏎ and ⎋ belong to the input method.
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
