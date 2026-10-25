import Foundation
import OSLog
import WebKit

/// Brings back to the front the page of a clicked notification: the app's windows (`MiniWindowManager`).
@MainActor
protocol PageNotificationRevealing: AnyObject {
    func reveal(_ page: BrowserTab)
}

/// Notifications of the pages (`PageNotificationScript`), shown by macOS (`SystemNotifications`): the website as
/// subtitle, grouped by website; a tag replaces the website's previous notification with the same tag. A click brings
/// the page back to the front (`revealer`), then gives it the `click` event. Also prepares, page by page, the decisions
/// the script reads at the start of each document. Made once for the app (`AppEnvironment`).
@MainActor
final class PageNotificationCenter {
    /// Most notifications remembered for their click; the oldest are forgotten.
    static let maximumTracked = 100

    weak var revealer: (any PageNotificationRevealing)?
    private let system: any SystemNotifications
    /// Shown notifications, from the oldest to the most recent.
    private var delivered: [Delivered] = []
    /// Last decisions given to the script of each page (content controller).
    private let preparedStates = NSMapTable<WKUserContentController, PreparedStates>.weakToStrongObjects()

    private struct Delivered {
        let identifier: String
        let scriptID: String
        weak var page: BrowserTab?
        weak var webView: WKWebView?
        let frame: WKFrameInfo
    }

    private final class PreparedStates {
        let isAvailable: Bool
        let states: [String: PageNotificationPermission]

        init(isAvailable: Bool, states: [String: PageNotificationPermission]) {
            self.isAvailable = isAvailable
            self.states = states
        }
    }

    init(system: any SystemNotifications) {
        self.system = system
        system.onActivate = { [weak self] in self?.activate($0) }
    }

    /// Before a navigation of `webView`: the decisions (origin key → permission) that the script will read in the next
    /// documents; `isAvailable` false: “denied” everywhere (private window). A new state script is added only if they
    /// changed: WebKit can't remove one, the last one added wins.
    func prepare(_ webView: WKWebView, isAvailable: Bool, states: [String: PageNotificationPermission]) {
        let controller = webView.configuration.userContentController
        if let prepared = preparedStates.object(forKey: controller), prepared.isAvailable == isAvailable, prepared.states == states {
            return
        }
        let source = PageNotificationScript.stateSource(isAvailable: isAvailable, states: states)
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
        preparedStates.setObject(PreparedStates(isAvailable: isAvailable, states: states), forKey: controller)
    }

    /// Asks macOS, the first time, whether Matcha may show notifications.
    @discardableResult
    func requestAuthorization() async -> Bool {
        await system.requestAuthorization()
    }

    /// Shows `content`, sent by `frame` of `page` (website `origin`); false if macOS refuses (notifications of Matcha
    /// turned off in System Settings).
    func post(
        _ content: PageNotificationContent,
        origin: SiteOrigin,
        page: BrowserTab,
        webView: WKWebView,
        frame: WKFrameInfo,
    ) async -> Bool {
        guard await system.requestAuthorization() else {
            Logger.notifications.notice("Notification not shown: turned off for Matcha")
            return false
        }
        // The tag belongs to the website: another one can't replace its notifications.
        let identifier = content.tag.isEmpty ? UUID().uuidString : "\(origin.key)#\(content.tag)"
        do {
            try await system.add(SystemNotification(
                identifier: identifier,
                title: content.title,
                subtitle: origin.displayName,
                body: content.body,
                threadIdentifier: origin.key,
                isSilent: content.isSilent,
            ))
        } catch {
            Logger.notifications.error("Notification not shown: \(error.logSummary, privacy: .public)")
            return false
        }
        track(Delivered(identifier: identifier, scriptID: content.scriptID, page: page, webView: webView, frame: frame))
        Logger.notifications.info("Notification shown (\(origin.displayHost, privacy: .private))")
        return true
    }

    /// `notification.close()` in the page of `webView`.
    func close(scriptID: String, in webView: WKWebView) {
        let closed = delivered.filter { $0.scriptID == scriptID && $0.webView === webView }
        delivered.removeAll { $0.scriptID == scriptID && $0.webView === webView }
        if !closed.isEmpty {
            system.removeDelivered(closed.map(\.identifier))
        }
    }

    private func track(_ entry: Delivered) {
        delivered.removeAll { $0.identifier == entry.identifier || $0.webView == nil }
        delivered.append(entry)
        if delivered.count > Self.maximumTracked {
            delivered.removeFirst(delivered.count - Self.maximumTracked)
        }
    }

    /// Click on a notification: its page comes to the front, then receives `click`. One from a page closed since, or
    /// from before the launch, only brings Matcha to the front (macOS does it).
    private func activate(_ identifier: String) {
        guard let index = delivered.lastIndex(where: { $0.identifier == identifier }) else {
            Logger.notifications.info("Notification clicked: its page is gone")
            return
        }
        let entry = delivered.remove(at: index)
        if let page = entry.page {
            revealer?.reveal(page)
        }
        guard let webView = entry.webView else {
            return
        }
        Logger.notifications.info("Notification clicked")
        Task {
            _ = try? await webView.callAsyncJavaScript(
                PageNotificationScript.dispatchBody,
                arguments: ["bridge": PageNotificationScript.bridgeName, "id": entry.scriptID, "type": "click"],
                in: entry.frame,
                contentWorld: .page,
            )
        }
    }
}
