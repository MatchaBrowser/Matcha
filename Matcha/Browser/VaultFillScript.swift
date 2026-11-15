import Foundation
import WebKit

/// The script of the vault's filling (`VAULT.md` § 8.3), in a content world of its own that the page doesn't see: it
/// tells the app which frames have a login form (`formsSource`), and which login was sent, to offer saving it
/// (`captureSource`), and which login field the user just reached, for the native list under it (`suggestSource`); it
/// fills only when the app calls it, for one frame, after checking again that the frame's origin is the one expected
/// (`fillSource`). It never fills by itself.
@MainActor
enum VaultFillScript {
    static let world = WKContentWorld.world(name: "MatchaVaultFill")
    static let handlerName = "matchaVault"

    /// Whether the pages talk to the filling: not while the vault is turned off on this Mac (`VaultService.isEnabled`).
    private(set) static var isEnabled = true

    static func install(in controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: world))
        if isEnabled {
            controller.add(VaultFillMessageHandler(), contentWorld: world, name: handlerName)
        }
    }

    /// Connects or disconnects a page's controller: without its handler, the script stops as soon as it starts, from
    /// the page's next load; a page already loaded can no longer post anything.
    static func setEnabled(_ enabled: Bool, in controller: WKUserContentController) {
        controller.removeScriptMessageHandler(forName: handlerName, contentWorld: world)
        if enabled {
            controller.add(VaultFillMessageHandler(), contentWorld: world, name: handlerName)
        }
    }

    /// For every page: those made from now on, and those of `controllers`.
    static func setEnabled(_ enabled: Bool, in controllers: [WKUserContentController]) {
        isEnabled = enabled
        for controller in controllers {
            setEnabled(enabled, in: controller)
        }
    }

    /// Fills a login in the frame; `expected` is the origin Matcha checked (`scheme://host[:port]`).
    static let fillBody = "return window.__matchaVaultFill?.(username, password, expected) ?? false;"
    /// Fills a one-time code in the frame.
    static let fillCodeBody = "return window.__matchaVaultFillCode?.(code, expected) ?? false;"
    /// Fills a new password (sign-up, change of password): its fields, and their confirmation.
    static let fillNewBody = "return window.__matchaVaultFillNew?.(password, expected) ?? false;"

    /// The whole script: its parts share the scope of one function, run once per frame.
    static let source = "(() => {\n" + formsSource + captureSource + suggestSource + fillSource + "})();\n"
}
