import AppKit

/// Délégué de l'application : liens ouverts par d'autres apps, confirmation avant de quitter.
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Adresses web et fichiers HTML que macOS confie à Matcha (tâche 8.2).
    func application(_: NSApplication, open urls: [URL]) {
        IncomingLinks.shared.receive(urls)
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        guard BrowserSettings.confirmsBeforeQuitting() else {
            return .terminateNow
        }
        let alert = NSAlert()
        alert.messageText = String(localized: "Quit Matcha?")
        alert.informativeText = String(localized: "Open tabs will be closed.")
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
