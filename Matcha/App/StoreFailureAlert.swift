import AppKit

/// Alert at launch when the store can't be opened or read (audit R2): the user decides, nothing is replaced silently.
@MainActor
enum StoreFailureAlert {
    static func ask(_ error: any Error) -> StoreFailureChoice {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = String(
            localized: "Matcha can't open its data.",
            comment: "Alert at launch when the tabs and Spaces can't be read",
        )
        alert.informativeText = String(
            localized: """
            Your tabs and Spaces couldn't be read (\(error.logSummary)). You can quit and try again later, start over \
            with new data (the unreadable data is kept aside, not deleted), or browse without saving anything.
            """,
            comment: "Alert at launch when the tabs and Spaces can't be read; %@ is the error code",
        )
        alert.addButton(withTitle: String(localized: "Quit", comment: "Button of the alert shown when the data can't be read"))
        alert.addButton(withTitle: String(
            localized: "Start Over",
            comment: "Button of the alert shown when the data can't be read: new data, the old kept aside",
        ))
        alert.addButton(withTitle: String(
            localized: "Continue Without Saving",
            comment: "Button of the alert shown when the data can't be read: browse in memory",
        ))
        NSApp.activate()
        return switch alert.runModal() {
        case .alertSecondButtonReturn: .startOver
        case .alertThirdButtonReturn: .continueWithoutSaving
        default: .quit
        }
    }
}
