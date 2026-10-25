import AppKit

/// “Clear History…”: a sheet alert on the history window, one button per period (the last hour, today, today and
/// yesterday, all history), then “Cancel” (Esc). An `NSAlert` rather than `confirmationDialog`: on macOS, SwiftUI
/// only shows four buttons there; with a fifth, the last period disappears and “Cancel” becomes “OK”
/// (`DECISIONS.md`).
@MainActor
enum HistoryClearAlert {
    /// `profileName`: name of the profile shown when there are several. `clear` receives the chosen period; nothing
    /// for “Cancel”. Without a window (or if it already has a sheet), the alert is a separate window.
    static func present(in window: NSWindow?, profileName: String?, clear: @escaping (HistoryPeriod) -> Void) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Clear History", comment: "Title of the dialog that clears the history")
        alert.informativeText = message(profileName: profileName)
        for period in HistoryPeriod.allCases {
            alert.addButton(withTitle: String(localized: period.title)).hasDestructiveAction = true
        }
        // No default button: Return erases nothing (review IU13).
        alert.buttons.first?.keyEquivalent = ""
        alert.addButton(withTitle: String(localized: "Cancel")).keyEquivalent = "\u{1b}"
        let handle = { (response: NSApplication.ModalResponse) in
            if let period = period(for: response) {
                clear(period)
            }
        }
        if let window, window.isVisible, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    /// Period of the `response` button (in the order of `HistoryPeriod.allCases`); nil for “Cancel”.
    nonisolated static func period(for response: NSApplication.ModalResponse) -> HistoryPeriod? {
        let index = response.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        return HistoryPeriod.allCases.indices.contains(index) ? HistoryPeriod.allCases[index] : nil
    }

    private static func message(profileName: String?) -> String {
        guard let name = profileName else {
            return String(
                localized: "Pages visited during this period are removed from the history. Cookies and website data are kept.",
                comment: "Clear History dialog, with a single profile",
            )
        }
        return String(
            localized: "Pages visited during this period are removed from the history of “\(name)”. Cookies and website data are kept.",
            comment: "Clear History dialog, with several profiles; %@ is the profile name",
        )
    }
}
