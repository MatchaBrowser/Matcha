import AppKit

/// Fermer la barre de recherche d'une page ; le clavier suit.
@MainActor
enum FindActions {
    /// ⎋ dans le champ et × : la barre se ferme, puis la page reprend le clavier si son champ l'avait (ou si
    /// personne ne l'a) ; jamais pris à un autre champ.
    static func close(_ page: BrowserTab) {
        releaseKeyboard(from: page)
        page.find.close()
        TabActivation.focusPage(of: page)
    }

    /// Rend le clavier à la fenêtre s'il est dans le champ de recherche de `page` (pas celui d'un autre panneau).
    private static func releaseKeyboard(from page: BrowserTab) {
        guard let window = page.webView?.window,
              let editor = window.firstResponder as? NSTextView, editor.isFieldEditor,
              let field = editor.delegate as? NSTextField,
              (field.delegate as? FindTextField.Coordinator)?.parent.pageID == page.id
        else {
            return
        }
        window.makeFirstResponder(nil)
    }
}
