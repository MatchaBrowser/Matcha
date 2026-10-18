import AppKit

/// « Effacer l'historique… » : alerte en feuille sur la fenêtre de l'historique, un bouton par période (la dernière
/// heure, aujourd'hui, aujourd'hui et hier, tout l'historique), puis « Annuler » (Échap). Une `NSAlert` et non
/// `confirmationDialog` : sous macOS, SwiftUI n'y montre que quatre boutons ; avec un cinquième, la dernière période
/// disparaît et « Annuler » devient « OK » (`DECISIONS.md`).
@MainActor
enum HistoryClearAlert {
    /// `profileName` : nom du profil montré quand il y en a plusieurs. `clear` reçoit la période choisie ; rien pour
    /// « Annuler ». Sans fenêtre (ou si elle a déjà une feuille), l'alerte est une fenêtre à part.
    static func present(in window: NSWindow?, profileName: String?, clear: @escaping (HistoryPeriod) -> Void) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Clear History", comment: "Title of the dialog that clears the history")
        alert.informativeText = message(profileName: profileName)
        for period in HistoryPeriod.allCases {
            alert.addButton(withTitle: String(localized: period.title)).hasDestructiveAction = true
        }
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

    /// Période du bouton `response` (dans l'ordre de `HistoryPeriod.allCases`) ; nil pour « Annuler ».
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
