import AppKit
import OSLog

/// Demande à l'utilisateur ce qu'une extension réclame en cours d'exécution (tâche 6.3). Une seule réponse, et vrai
/// seulement s'il accepte : rien n'est jamais accordé d'office. Remplacé dans les tests.
@MainActor
protocol ExtensionPermissionPrompting: AnyObject {
    func ask(_ request: ExtensionPermissionRequest, completion: @escaping @MainActor (Bool) -> Void)
}

/// Alerte minimale, en feuille sur la fenêtre principale de l'app : le nom de l'extension, les permissions et les sites
/// demandés, « Refuser » (bouton par défaut : Entrée n'accorde rien) et « Autoriser ». L'écran des permissions de la tâche 6.4
/// (panneau intégré) la remplacera. Sans fenêtre, la demande est refusée.
@MainActor
final class ExtensionPermissionAlert: ExtensionPermissionPrompting {
    func ask(_ request: ExtensionPermissionRequest, completion: @escaping @MainActor (Bool) -> Void) {
        guard let window = NSApp.mainWindow ?? NSApp.keyWindow, window.attachedSheet == nil else {
            Logger.extensions.notice("Demande de permissions refusée : aucune fenêtre pour la montrer")
            completion(false)
            return
        }
        let alert = NSAlert()
        alert.messageText = String(
            localized: "“\(request.extensionName)” Requests Additional Access",
            comment: "Alert shown when a browser extension asks for more permissions; %@ is the extension name",
        )
        alert.informativeText = Self.details(of: request)
        // Refuser d'abord : c'est le bouton par défaut.
        alert.addButton(withTitle: String(
            localized: "Extension Prompt Deny",
            defaultValue: "Don't Allow",
            comment: "Extension permission alert: refuse what the extension asks for",
        ))
        alert.addButton(withTitle: String(
            localized: "Extension Prompt Allow",
            defaultValue: "Allow",
            comment: "Extension permission alert: grant what the extension asks for",
        ))
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                completion(response == .alertSecondButtonReturn)
            }
        }
    }

    /// Lignes de l'alerte : permissions, puis sites (ou « Tous les sites »), listes au format de la langue.
    static func details(of request: ExtensionPermissionRequest) -> String {
        var lines: [String] = []
        if !request.permissions.isEmpty {
            let list = request.permissions.formatted(.list(type: .and))
            lines.append(String(
                localized: "Permissions: \(list)",
                comment: "Extension permission alert; %@ lists technical permission names",
            ))
        }
        if request.allWebsites {
            lines.append(String(localized: "Websites: all websites", comment: "Extension permission alert: access to every website"))
        } else if !request.websites.isEmpty {
            let list = request.websites.formatted(.list(type: .and))
            lines.append(String(
                localized: "Websites: \(list)",
                comment: "Extension permission alert; %@ lists websites or address patterns",
            ))
        }
        return lines.joined(separator: "\n")
    }
}
