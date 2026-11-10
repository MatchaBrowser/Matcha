import OSLog
import WebKit

/// Messages of the vault's script (`VaultFillScript`), from its own content world only: the page can't send them.
final class VaultFillMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated {
            guard let parsed = VaultFormMessage(body: message.body) else {
                Logger.vault.notice("Malformed vault script message: refused")
                return
            }
            guard let webView = message.webView as? BrowserWebView else {
                return
            }
            webView.vaultForms?.receive(parsed, from: message.frameInfo)
        }
    }
}

/// What the vault's script says about a frame.
nonisolated enum VaultFormMessage: Equatable, Sendable {
    /// The frame has (or no longer has) a password field, a lone user name field (a first step), a sign-up form.
    case forms(hasPassword: Bool, hasUsername: Bool, isSignup: Bool)
    /// A form with a password was sent.
    case submitted(username: String, password: String, isSignup: Bool)

    init?(body: Any) {
        guard let body = body as? [String: Any], let type = body["type"] as? String else {
            return nil
        }
        switch type {
        case "forms":
            self = .forms(
                hasPassword: body["hasPassword"] as? Bool ?? false,
                hasUsername: body["hasUsername"] as? Bool ?? false,
                isSignup: body["isSignup"] as? Bool ?? false,
            )
        case "submitted":
            guard let password = body["password"] as? String, !password.isEmpty, password.count <= 1024 else {
                return nil
            }
            let username = String((body["username"] as? String ?? "").prefix(512))
            self = .submitted(username: username, password: password, isSignup: body["isSignup"] as? Bool ?? false)
        default:
            return nil
        }
    }
}

/// Who takes the vault script's messages of a web view: its tab (`VaultPageForms`).
@MainActor
protocol VaultFormReceiving: AnyObject {
    func receive(_ message: VaultFormMessage, from frame: WKFrameInfo)
}
