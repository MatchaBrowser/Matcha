import Foundation
import OSLog
import WebKit

/// Brings back to the front the page of a clicked notification: the app's windows (`MiniWindowManager`).
@MainActor
protocol PageNotificationRevealing: AnyObject {
    func reveal(_ page: BrowserTab)
}

/// Notifications of the pages (`PageNotificationScript`), shown by macOS (`SystemNotifications`): the website as
/// subtitle, grouped by website and profile; a tag replaces the previous notification with the same tag of the same
/// website in the same profile, never another profile's (review SV7). A click brings
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
    /// What the state scripts of each page (content controller) already give its documents.
    private let preparedStates = NSMapTable<WKUserContentController, PreparedStates>.weakToStrongObjects()

    /// Where a notification comes from: its page, its web view and the frame that sent it.
    struct Sender {
        let page: BrowserTab
        let webView: WKWebView
        let frame: WKFrameInfo
    }

    private struct Delivered {
        let identifier: String
        let scriptID: String
        weak var page: BrowserTab?
        weak var webView: WKWebView?
        let frame: WKFrameInfo
    }

    private final class PreparedStates {
        var isAvailable: Bool?
        /// Decision of each website already given; a website missing is “default”.
        var states: [String: PageNotificationPermission] = [:]
    }

    init(system: any SystemNotifications) {
        self.system = system
        system.onActivate = { [weak self] in self?.activate($0) }
    }

    /// Before a navigation of `webView` to the website `origin` (its key): its decision, which the script will read in
    /// the next documents, in its isolated world; `isAvailable` false: “denied” everywhere (private window). Only the
    /// destination's decision, never the profile's others (review WB10). A state script is added only when it changes
    /// what the page's scripts already give: WebKit can only remove all the scripts of a page at once, the extensions'
    /// included; they run in order, the last one wins.
    func prepare(_ webView: WKWebView, isAvailable: Bool, origin: String?, permission: PageNotificationPermission) {
        let controller = webView.configuration.userContentController
        let prepared = preparedStates.object(forKey: controller) ?? PreparedStates()
        let website = isAvailable ? origin : nil
        let changesState = website.map { (prepared.states[$0] ?? .default) != permission } ?? false
        guard prepared.isAvailable != isAvailable || changesState else {
            return
        }
        let source = PageNotificationScript.stateSource(
            isAvailable: isAvailable,
            origin: changesState ? website : nil,
            permission: permission,
        )
        controller.addUserScript(WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false,
            in: PageNotificationScript.world,
        ))
        prepared.isAvailable = isAvailable
        if changesState, let website {
            prepared.states[website] = permission
        }
        preparedStates.setObject(prepared, forKey: controller)
    }

    /// The decision of `origin` (its key) changed in the settings while `webView` shows it: the displayed document reads
    /// it at once, the next ones from their state script.
    func update(_ webView: WKWebView, origin: String, permission: PageNotificationPermission) {
        prepare(webView, isAvailable: true, origin: origin, permission: permission)
        webView.callAsyncJavaScript(
            PageNotificationScript.stateBody,
            arguments: ["bridge": PageNotificationScript.bridgeName, "origin": origin, "state": permission.rawValue],
            in: nil,
            in: PageNotificationScript.world,
        )
    }

    /// Asks macOS, the first time, whether Matcha may show notifications.
    @discardableResult
    func requestAuthorization() async -> Bool {
        await system.requestAuthorization()
    }

    /// Shows `content`, sent by `sender` (website `origin`, profile `profileID`); false if macOS refuses (notifications
    /// of Matcha turned off in System Settings).
    func post(_ content: PageNotificationContent, origin: SiteOrigin, profileID: UUID?, from sender: Sender) async -> Bool {
        guard await system.requestAuthorization() else {
            Logger.notifications.notice("Notification not shown: turned off for Matcha")
            return false
        }
        // The tag belongs to the website in its profile: another website or profile can't replace its notifications.
        let thread = Self.threadIdentifier(origin: origin, profileID: profileID)
        let identifier = content.tag.isEmpty ? UUID().uuidString : "\(thread)#\(content.tag)"
        do {
            try await system.add(SystemNotification(
                identifier: identifier,
                title: content.title,
                subtitle: origin.displayName,
                body: content.body,
                threadIdentifier: thread,
                isSilent: content.isSilent,
            ))
        } catch {
            Logger.notifications.error("Notification not shown: \(error.logSummary, privacy: .public)")
            return false
        }
        track(Delivered(
            identifier: identifier,
            scriptID: content.scriptID,
            page: sender.page,
            webView: sender.webView,
            frame: sender.frame,
        ))
        Logger.notifications.info("Notification shown (\(origin.displayHost, privacy: .private))")
        return true
    }

    /// Group of the notifications of `origin` in profile `profileID`.
    static func threadIdentifier(origin: SiteOrigin, profileID: UUID?) -> String {
        "\(profileID?.uuidString ?? "default") \(origin.key)"
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
                contentWorld: PageNotificationScript.world,
            )
        }
    }
}
