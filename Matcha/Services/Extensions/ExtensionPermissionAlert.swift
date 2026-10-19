import AppKit
import OSLog

/// Asks the user what an extension requests while running (task 6.3). A single answer, and true only if the user
/// accepts: nothing is ever granted automatically. Replaced in the tests.
@MainActor
protocol ExtensionPermissionPrompting: AnyObject {
    func ask(_ request: ExtensionPermissionRequest, completion: @escaping @MainActor (Bool) -> Void)
}

/// Alert as a sheet on the app's main window: the extension's name, the requested permissions and websites, “Don't
/// Allow” (default button: Return grants nothing) and “Allow”. AppKit queues it behind a sheet already open (audit
/// E5: a request is no longer refused for that). Without a window, the request is denied.
@MainActor
final class ExtensionPermissionAlert: ExtensionPermissionPrompting {
    func ask(_ request: ExtensionPermissionRequest, completion: @escaping @MainActor (Bool) -> Void) {
        guard let window = NSApp.mainWindow ?? NSApp.keyWindow else {
            Logger.extensions.notice("Permission request denied: no window to show it")
            completion(false)
            return
        }
        let alert = NSAlert()
        alert.messageText = String(
            localized: "“\(request.extensionName)” Requests Additional Access",
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
                completion(response == .alertSecondButtonReturn)
            }
        }
    }

    /// Lines of the alert: permissions, then websites (or “all websites”), lists in the language's format.
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
