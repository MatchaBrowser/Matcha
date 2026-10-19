import AppKit
import CoreServices

/// The alert before quitting (audit R7): only if the user asked for it in Settings (off by default: tabs come back at
/// the next launch), and never when the Mac logs out, restarts or shuts down, which it would hold up.
@MainActor
enum QuitConfirmation {
    /// Quit reasons (`kAEQuitReason`) of the system: log out, restart, shut down.
    nonisolated static let systemReasons: Set<OSType> = [
        OSType(kAELogOut), OSType(kAEReallyLogOut), OSType(kAEShowRestartDialog), OSType(kAERestart),
        OSType(kAEShowShutdownDialog), OSType(kAEShutDown),
    ]

    nonisolated static func asks(isEnabled: Bool, quitReason: OSType?) -> Bool {
        isEnabled && !(quitReason.map(systemReasons.contains) ?? false)
    }

    /// Reason of the quit Apple event being handled, if any.
    static var currentQuitReason: OSType? {
        NSAppleEventManager.shared().currentAppleEvent?.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason))?.enumCodeValue
    }

    static func shouldTerminate() -> NSApplication.TerminateReply {
        guard asks(isEnabled: BrowserSettings.confirmsBeforeQuitting(), quitReason: currentQuitReason) else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit Matcha?")
        alert.informativeText = String(
            localized: "Your tabs will be there the next time you open Matcha. Private windows and downloads in progress will be closed.",
            comment: "Alert before quitting, if the user asked for it",
        )
        alert.addButton(withTitle: String(localized: "Quit", comment: "Button of the alert shown before quitting"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = String(localized: "Do not ask again")
        let response = alert.runModal()
        if alert.suppressionButton?.state == .on {
            UserDefaults.standard.set(false, forKey: BrowserSettings.Key.confirmBeforeQuitting)
        }
        return response == .alertFirstButtonReturn ? .terminateNow : .terminateCancel
    }
}
