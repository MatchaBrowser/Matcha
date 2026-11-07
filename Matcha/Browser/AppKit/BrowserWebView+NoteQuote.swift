import AppKit
import OSLog
import WebKit

/// “Add to Note” in the menu of a selection (task 12.6): right after “Copy”, on a website, when the window keeps notes.
/// The selection is read in an isolated world (`.defaultClient`), never by the page's own code.
extension BrowserWebView {
    static let addToNoteIdentifier = "MatchaMenuItemIdentifierAddToNote"

    /// Adds the item to `menu` if it is the menu of a selection.
    func addNoteQuoteItem(to menu: NSMenu) {
        guard let noteQuotes, noteQuotes.acceptsQuotes, let page = backForwardList.currentItem?.url, SiteOrigin.web(of: page) != nil,
              let index = PageMenuPlan.noteQuoteIndex(for: menu.items.map { $0.identifier?.rawValue })
        else {
            return
        }
        let item = NSMenuItem(
            title: String(localized: "Add to Note", comment: "Context menu of selected text: adds it to the note of the page"),
            action: #selector(addSelectionToNote(_:)),
            keyEquivalent: "",
        )
        item.identifier = NSUserInterfaceItemIdentifier(Self.addToNoteIdentifier)
        item.target = self
        if menu.items.contains(where: { $0.image != nil }) {
            item.image = NSImage(systemSymbolName: "text.quote", accessibilityDescription: nil)
        }
        menu.insertItem(item, at: index)
    }

    @objc private func addSelectionToNote(_: NSMenuItem) {
        guard let page = backForwardList.currentItem?.url else {
            return
        }
        let title = title
        Task {
            do {
                let selection = try await callAsyncJavaScript(
                    "return String(window.getSelection() ?? '').slice(0, limit);",
                    arguments: ["limit": NoteQuote.maximumLength * 2],
                    contentWorld: .defaultClient,
                ) as? String
                guard let selection, !NoteQuote.cleaned(selection).isEmpty else {
                    return
                }
                noteQuotes?.addQuote(selection, from: page, title: title)
                Logger.notes.info("Passage added to the page's note")
            } catch {
                Logger.notes.error("Selection not read: \(error.logSummary, privacy: .public)")
            }
        }
    }
}
