import AppKit
import OSLog

/// Alert as a sheet on the app's main window: the extension's name, what the requested permissions let it do, the
/// websites, “Don't Allow” (default button: Return grants nothing) and “Allow”. AppKit queues it behind a sheet already
/// open (audit E5: a request is no longer refused for that). Without a window, the request isn't shown: `notAsked`.
@MainActor
final class ExtensionPermissionAlert: ExtensionPermissionPrompting {
    func ask(_ request: ExtensionPermissionRequest, completion: @escaping @MainActor (ExtensionPermissionAnswer) -> Void) {
        guard let window = NSApp.mainWindow ?? NSApp.keyWindow else {
            Logger.extensions.notice("Permission request not shown: no window")
            completion(.notAsked)
            return
        }
        let alert = NSAlert()
        alert.messageText = String(
            localized: "“\(ExtensionDisplayName.cleaned(request.extensionName))” Requests Additional Access",
            comment: "Alert shown when a browser extension asks for more permissions; %@ is the extension name",
        )
        alert.informativeText = Self.details(of: request)
        // “Don't Allow” first: it is the default button.
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
                completion(response == .alertSecondButtonReturn ? .allowed : .denied)
            }
        }
    }

    /// Lines of the alert: what the permissions let the extension do, in the words of the permissions screen
    /// (review EX27), then websites (or “all websites”), lists in the language's format.
    static func details(of request: ExtensionPermissionRequest) -> String {
        var lines = ExtensionPermissionSummary.lines(permissions: Set(request.permissions), hosts: []).map(\.title)
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
