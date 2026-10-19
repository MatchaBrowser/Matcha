import AppKit

/// Closing a page's find bar; keyboard focus follows.
@MainActor
enum FindActions {
    /// ⎋ in the field and ×: the bar closes, then the page takes keyboard focus back if its field had it (or if
    /// nobody has it); never taken from another field.
    static func close(_ page: BrowserTab) {
        releaseKeyboard(from: page)
        page.find.close()
        TabActivation.focusPage(of: page)
    }

    /// Gives keyboard focus back to the window if it is in the find field of `page` (not that of another pane).
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
