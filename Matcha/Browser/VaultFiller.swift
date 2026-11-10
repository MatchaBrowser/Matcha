import Foundation
import OSLog
import WebKit

/// Fills a frame of a page with a login of the vault (`VAULT.md` § 8.3): only the frame named, through the vault's
/// own content world, and only if the frame is still at the origin Matcha checked.
@MainActor
enum VaultFiller {
    /// Fills `username` and `password` in `frame`; false if nothing was filled (the frame changed, no field).
    static func fill(_ frame: VaultPageForms.Frame, in webView: WKWebView, username: String, password: String) async -> Bool {
        await call(
            VaultFillScript.fillBody,
            arguments: ["username": username, "password": password, "expected": frame.origin],
            in: frame,
            webView: webView,
        )
    }

    /// Fills a new password in the sign-up or change of password form of `frame`.
    static func fillNewPassword(_ password: String, in frame: VaultPageForms.Frame, webView: WKWebView) async -> Bool {
        await call(VaultFillScript.fillNewBody, arguments: ["password": password, "expected": frame.origin], in: frame, webView: webView)
    }

    /// Fills a one-time code in `frame`.
    static func fillCode(_ code: String, in frame: VaultPageForms.Frame, webView: WKWebView) async -> Bool {
        await call(VaultFillScript.fillCodeBody, arguments: ["code": code, "expected": frame.origin], in: frame, webView: webView)
    }

    private static func call(_ body: String, arguments: [String: Any], in frame: VaultPageForms.Frame, webView: WKWebView) async -> Bool {
        do {
            let result = try await webView.callAsyncJavaScript(
                body,
                arguments: arguments,
                in: frame.info,
                contentWorld: VaultFillScript.world,
            )
            return result as? Bool ?? false
        } catch {
            Logger.vault.notice("Fill not done: \(error.logSummary, privacy: .public)")
            return false
        }
    }
}
