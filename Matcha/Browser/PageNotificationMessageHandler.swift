import OSLog
import WebKit

/// Receives the messages of the notification script, from its isolated world only (`PageNotificationScript.world`),
/// and hands them to the recipient that the page's web view holds (`BrowserWebView.notifications`: its navigation
/// delegate, `NavigationCoordinator+Notifications`), which answers. A malformed message, or one from a page without a
/// recipient, gets a refusal.
final class PageNotificationMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void,
    ) {
        guard let parsed = PageNotificationMessage(body: message.body) else {
            Logger.notifications.notice("Malformed notification script message: refused")
            replyHandler(nil, "Malformed message")
            return
        }
        guard let webView = message.webView as? BrowserWebView, let recipient = webView.notifications else {
            replyHandler(nil, "No page")
            return
        }
        recipient.receive(parsed, from: message.frameInfo, in: webView) { replyHandler($0, nil) }
    }
}

/// Recipient of a page's notification messages (`PageNotificationMessageHandler`), held weakly by its web view.
@MainActor
protocol PageNotificationReceiving: AnyObject {
    func receive(
        _ message: PageNotificationMessage,
        from frame: WKFrameInfo,
        in webView: WKWebView,
        reply: @escaping @MainActor @Sendable (Any?) -> Void,
    )
}
