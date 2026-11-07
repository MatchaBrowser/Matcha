import Foundation
import OSLog
import WebKit

/// WebKit's side of the notes editor (`NoteEditor`): the bridge's messages, read from its world only; the page as the
/// only navigation; the links of the note (http or https) handed to the browser, any other address refused; the
/// page's process that stops. Holds the editor weakly: WebKit holds this object.
@MainActor
final class NoteEditorDelegate: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    weak var editor: NoteEditor?

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let parsed = NoteEditorMessage(body: message.body) else {
            Logger.notes.notice("Malformed note editor message: refused")
            return
        }
        editor?.receive(parsed)
    }

    func webView(_: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else {
            return .cancel
        }
        if navigationAction.targetFrame?.isMainFrame == true, NoteEditorResources.isPage(url) {
            return .allow
        }
        if navigationAction.navigationType == .linkActivated {
            open(url)
        }
        return .cancel
    }

    /// “Open link” in the note (`window.open`): the browser opens it; the editor never makes a window.
    func webView(
        _: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures _: WKWindowFeatures,
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            open(url)
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        editor?.pageDidTerminate()
    }

    private func open(_ url: URL) {
        guard SiteOrigin.web(of: url) != nil else {
            return
        }
        editor?.openLink?(url)
    }
}
