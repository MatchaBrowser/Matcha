import AppKit

/// Champ de la barre de commande et de la barre de recherche dans la page : il prend le clavier dans la mise à jour
/// même qui l'insère, pour qu'aucune frappe tapée juste après ⌘T (ou ⌘F) n'atteigne la page.
final class CommandBarNSTextField: NSTextField {
    override static var cellClass: AnyClass? {
        get { CommandBarFieldCell.self }
        set { super.cellClass = newValue }
    }

    /// Le champ doit prendre le clavier dès qu'il sera dans une fenêtre.
    var wantsFocus = false
    /// Appelé quand le champ prend le clavier (clic, ⌘F).
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

    /// Jamais makeFirstResponder sur un champ déjà en édition : l'édition se terminerait et fermerait la barre.
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

/// Cellule du champ, avec son propre éditeur : pas de guillemets typographiques, de tirets, de
/// remplacements ni de correction, qui fausseraient une adresse ou une recherche exacte. L'éditeur
/// partagé de la fenêtre (champ de nom de dossier) garde les réglages de l'utilisateur.
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
