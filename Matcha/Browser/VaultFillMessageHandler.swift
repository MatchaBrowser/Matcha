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
    /// The user name of a first step was sent: its password comes on the next page.
    case username(String)
    /// The user just reached a login field: the native list goes under it (`VAULT.md` § 8.1).
    case field(VaultFieldPlace)
    /// That field no longer wants the list: typed in, left, scrolled away.
    case fieldDone

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
        case "username":
            guard let username = body["username"] as? String, !username.isEmpty else {
                return nil
            }
            self = .username(String(username.prefix(512)))
        case "field":
            guard let place = VaultFieldPlace(body: body) else {
                return nil
            }
            self = .field(place)
        case "fieldDone":
            self = .fieldDone
        default:
            return nil
        }
    }
}

/// Where a login field is in the main frame, in CSS pixels of its viewport (`innerWidth` × `innerHeight`, scroll bars
/// included): the app scales it to the web view's size, whatever the page's zoom.
nonisolated struct VaultFieldPlace: Hashable, Sendable {
    let left: Double
    let top: Double
    let width: Double
    let height: Double
    let viewportWidth: Double
    let viewportHeight: Double

    init(left: Double, top: Double, width: Double, height: Double, viewportWidth: Double, viewportHeight: Double) {
        (self.left, self.top, self.width, self.height) = (left, top, width, height)
        (self.viewportWidth, self.viewportHeight) = (viewportWidth, viewportHeight)
    }

    init?(body: [String: Any]) {
        let keys = ["x", "y", "width", "height", "viewportWidth", "viewportHeight"]
        let values = keys.compactMap { (body[$0] as? NSNumber)?.doubleValue }.filter { $0.isFinite && abs($0) < 1_000_000 }
        guard values.count == keys.count, values[2] >= 0, values[3] >= 0, values[4] > 0, values[5] > 0 else {
            return nil
        }
        self.init(left: values[0], top: values[1], width: values[2], height: values[3], viewportWidth: values[4], viewportHeight: values[5])
    }
}

/// A key for the list under a login field (`VAULT.md` § 8.1): ↓, ↑, ↩ (or ⌤), ⎋.
nonisolated enum VaultSuggestionKey: Sendable {
    case next
    case previous
    case choose
    case close
}

/// Who takes the vault script's messages of a web view: its tab (`VaultPageForms`).
@MainActor
protocol VaultFormReceiving: AnyObject {
    func receive(_ message: VaultFormMessage, from frame: WKFrameInfo)
    /// Whether the list under the field takes `key`, which the page then doesn't get.
    func takeSuggestionKey(_ key: VaultSuggestionKey) -> Bool
}
