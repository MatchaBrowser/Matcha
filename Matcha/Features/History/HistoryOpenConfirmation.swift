import AppKit

/// Opening many rows of the history at once (⌘A then Return) asks first: beyond `maximumWithoutAsking` pages, an alert
/// on the history window (review IU14).
@MainActor
enum HistoryOpenConfirmation {
    /// Most pages opened without asking.
    nonisolated static let maximumWithoutAsking = 20

    nonisolated static func asks(count: Int) -> Bool {
        count > maximumWithoutAsking
    }

    /// Runs `open` at once for a few pages, otherwise once the user confirms.
    static func confirm(count: Int, in window: NSWindow?, open: @escaping () -> Void) {
        guard asks(count: count) else {
            open()
            return
        }
        let alert = NSAlert()
        alert.messageText = String(
            localized: "Open \(count) pages in new tabs?",
            comment: "History window: confirmation before opening many rows at once; %lld is the number of pages (more than 20)",
        )
        alert.addButton(withTitle: String(localized: "Open All", comment: "History window: button that opens all the selected pages"))
        alert.addButton(withTitle: String(localized: "Cancel")).keyEquivalent = "\u{1b}"
        let handle = { (response: NSApplication.ModalResponse) in
            if response == .alertFirstButtonReturn {
                open()
            }
        }
        if let window, window.isVisible, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }
}
