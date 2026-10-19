import AppKit

/// Field of the command bar and of the find-in-page bar: it takes the keyboard in the very update that inserts it,
/// so that no keystroke typed right after ⌘T (or ⌘F) reaches the page.
final class CommandBarNSTextField: NSTextField {
    override static var cellClass: AnyClass? {
        get { CommandBarFieldCell.self }
        set { super.cellClass = newValue }
    }

    /// The field must take the keyboard as soon as it is in a window.
    var wantsFocus = false
    /// Called when the field takes the keyboard (click, ⌘F).
    var onBecomeFirstResponder: (() -> Void)?

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            onBecomeFirstResponder?()
        }
        return became
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if wantsFocus {
            focusAndSelectAll()
        }
    }

    /// Never makeFirstResponder on a field already being edited: editing would end and close the bar.
    func focusAndSelectAll() {
        guard let window else {
            wantsFocus = true
            return
        }
        wantsFocus = false
        if currentEditor() == nil {
            window.makeFirstResponder(self)
        }
        currentEditor()?.selectAll(nil)
    }
}

/// Cell of the field, with its own editor: no smart quotes, dashes, substitutions or correction, which would
/// distort an exact address or search. The window's shared editor (folder name field) keeps the user's settings.
final class CommandBarFieldCell: NSTextFieldCell {
    private lazy var editor: NSTextView = {
        let editor = NSTextView()
        editor.isFieldEditor = true
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.isAutomaticLinkDetectionEnabled = false
        editor.isAutomaticDataDetectionEnabled = false
        editor.isAutomaticTextCompletionEnabled = false
        return editor
    }()

    override func fieldEditor(for _: NSView) -> NSTextView? {
        editor
    }
}
