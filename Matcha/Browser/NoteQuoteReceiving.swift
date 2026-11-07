import Foundation

/// Recipient of the passages a page's menu adds to its note (task 12.6, “Add to Note”): the notes panel of the window
/// that shows the page, given to its web views like the translation host.
@MainActor
protocol NoteQuoteReceiving: AnyObject {
    /// False when no note can be kept (private window): the menu doesn't offer the item.
    var acceptsQuotes: Bool { get }
    /// Adds `passage`, selected in the page at `page` (its document), titled `title`, to the page's note.
    func addQuote(_ passage: String, from page: URL, title: String?)
}
