import OSLog
import WebKit

/// Receives the messages of the notification script, from its isolated world only (`PageNotificationScript.world`),
/// and hands them to the navigation delegate of the page that sends them (`NavigationCoordinator+Notifications`), which
/// answers. A malformed message, or one from a page without a delegate, gets a refusal.
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
        guard let webView = message.webView, let coordinator = webView.navigationDelegate as? NavigationCoordinator else {
            replyHandler(nil, "No page")
            return
        }
        coordinator.receive(parsed, from: message.frameInfo, in: webView) { replyHandler($0, nil) }
    }
}
