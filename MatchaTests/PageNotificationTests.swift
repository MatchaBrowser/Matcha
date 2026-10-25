import Foundation
@testable import Matcha
import Testing
import WebKit

/// Notifications of a real page (`PageNotificationScript`): the permission read from the start of the document, the
/// request through the banner, showing, closing and clicking, with a fake of macOS's notifications. The pages are
/// local HTML with an https address (`loadHTMLString`), never loaded from the network.
@MainActor
struct PageNotificationTests {
    private let system = FakeSystemNotifications()
    private let center: PageNotificationCenter
    private let revealer = FakeNotificationRevealer()
    private let session: BrowserSession
    private let window = AudioTestWindow()
    private let origin = SiteOrigin(scheme: "https", host: "notify.example.com", port: nil)!

    init() throws {
        center = PageNotificationCenter(system: system)
        center.revealer = revealer
        session = try BrowserSession(
            container: BrowserSchema.makeContainer(inMemory: true),
            services: SessionServices(notifications: center),
        )
    }

    private var manager: TabManager {
        session.spaces[0].tabManager
    }

    /// Selected tab showing `head` (scripts run while the document is read) and `body` at `address` (that of `origin`).
    private func open(
        head: String = "",
        body: String = "",
        address: String = "https://notify.example.com/",
        in manager: TabManager? = nil,
    ) async throws -> BrowserTab {
        let manager = manager ?? self.manager
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        window.show(tab.loadedWebView)
        let html = "<html><head><title>notifications</title>\(head)</head><body>\(body)</body></html>"
        tab.loadedWebView.loadHTMLString(html, baseURL: URL(string: address))
        try await waitUntil { tab.title == "notifications" && !tab.isLoading }
        return tab
    }

    private func evaluate(_ script: String, in tab: BrowserTab) async throws -> Any? {
        try await tab.loadedWebView.callAsyncJavaScript(script, contentWorld: .page)
    }

    /// Waits until `script` returns true in the page.
    private func waitUntilTrue(_ script: String, in tab: BrowserTab) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while try await evaluate(script, in: tab) as? Bool != true {
            guard clock.now < deadline else {
                throw WaitTimeoutError(line: #line)
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    @Test func `a page reads the remembered decision from the start of its document`() async throws {
        manager.sitePermissions?.set(.allow, for: .notifications, origin: origin)
        let tab = try await open(head: "<script>window.early = Notification.permission;</script>")
        #expect(try await evaluate("return window.early", in: tab) as? String == "granted")
        let query = "return (await navigator.permissions.query({ name: 'notifications' })).state"
        #expect(try await evaluate(query, in: tab) as? String == "granted")
        #expect(tab.canSendNotifications)

        manager.sitePermissions?.set(.deny, for: .notifications, origin: origin)
        let denied = try await open(head: "<script>window.early = Notification.permission;</script>")
        #expect(try await evaluate("return window.early", in: denied) as? String == "denied")
        #expect(!denied.canSendNotifications)
    }

    @Test func `an undecided website asks in the banner and the answer is remembered`() async throws {
        let tab = try await open()
        #expect(try await evaluate("return Notification.permission", in: tab) as? String == "default")
        _ = try await evaluate("Notification.requestPermission().then((answer) => { window.answer = answer; }); return true", in: tab)
        try await waitUntil { tab.permissionPrompts.current?.asked == [.notifications] }
        tab.permissionPrompts.answer(.alwaysAllow)
        try await waitUntilTrue("return window.answer === 'granted' && Notification.permission === 'granted'", in: tab)
        #expect(manager.sitePermissions?.decision(.notifications, for: origin) == .allow)
        #expect(tab.canSendNotifications)
        try await waitUntil { system.authorizationRequests > 0 }
    }

    @Test func `without a click a page can't ask`() async throws {
        let tab = try await open(head: "<script>Notification.requestPermission().then((answer) => { window.answer = answer; });</script>")
        try await waitUntilTrue("return window.answer === 'default'", in: tab)
        #expect(tab.permissionPrompts.current == nil)
    }

    @Test func `an allowed website shows its notifications and a click brings its page back`() async throws {
        manager.sitePermissions?.set(.allow, for: .notifications, origin: origin)
        let tab = try await open()
        _ = try await evaluate("""
        const notification = new Notification('Nouveau message', { body: 'Bonjour', tag: 'boite' });
        notification.onshow = () => { window.shown = true; };
        notification.onclick = () => { window.clicked = true; };
        window.notification = notification;
        return true
        """, in: tab)
        try await waitUntilTrue("return window.shown === true", in: tab)
        #expect(system.added == [SystemNotification(
            identifier: "https://notify.example.com#boite",
            title: "Nouveau message",
            subtitle: "notify.example.com",
            body: "Bonjour",
            threadIdentifier: "https://notify.example.com",
            isSilent: false,
        )])

        system.onActivate?("https://notify.example.com#boite")
        #expect(revealer.revealed.map(\.id) == [tab.id])
        try await waitUntilTrue("return window.clicked === true", in: tab)

        // Shown again, then closed by the page: macOS removes it.
        _ = try await evaluate("window.again = new Notification('Encore', { tag: 'boite' }); return true", in: tab)
        try await waitUntil { system.added.count == 2 }
        _ = try await evaluate("window.again.close(); return true", in: tab)
        try await waitUntil { system.removed == ["https://notify.example.com#boite"] }
    }

    @Test func `a denied website or a private window can't notify`() async throws {
        manager.sitePermissions?.set(.deny, for: .notifications, origin: origin)
        let tab = try await open()
        _ = try await evaluate("new Notification('Non').onerror = () => { window.failed = true; }; return true", in: tab)
        try await waitUntilTrue("return window.failed === true", in: tab)
        #expect(system.added.isEmpty)

        let privateSession = try BrowserSession(
            container: BrowserSchema.makeContainer(inMemory: true),
            isPrivate: true,
            services: SessionServices(notifications: center),
        )
        let page = try await open(in: privateSession.spaces[0].tabManager)
        #expect(try await evaluate("return Notification.permission", in: page) as? String == "denied")
        _ = try await evaluate("Notification.requestPermission().then((answer) => { window.answer = answer; }); return true", in: page)
        try await waitUntilTrue("return window.answer === 'denied'", in: page)
        #expect(page.permissionPrompts.current == nil)
    }

    /// Review WB2: the page can't reach the app's recipient, which lives in an isolated world.
    @Test func `a page can't write to the app directly`() async throws {
        let tab = try await open()
        #expect(try await evaluate("return typeof window.webkit?.messageHandlers?.matchaNotifications", in: tab) as? String == "undefined")
        #expect(try await evaluate("return Object.keys(window).some((key) => key.includes('atcha'))", in: tab) as? Bool == false)
    }

    /// Review WB2: a burst of requests after one click gives one banner.
    @Test func `a burst of requests waits once in the banner`() async throws {
        let tab = try await open()
        _ = try await evaluate("""
        window.answers = [];
        for (let i = 0; i < 5; i++) {
            Notification.requestPermission().then((answer) => { window.answers.push(answer); });
        }
        return true
        """, in: tab)
        try await waitUntilTrue("return window.answers.length === 4", in: tab)
        #expect(tab.permissionPrompts.requests.count == 1)
        tab.permissionPrompts.answer(.alwaysAllow)
        try await waitUntilTrue("return window.answers.length === 5 && window.answers[4] === 'granted'", in: tab)
    }

    /// Review WB2: a frame of another site (here, an opaque origin) and an insecure page read “denied” and never ask.
    @Test func `a frame of another site or an http page can't ask`() async throws {
        let request = "Notification.requestPermission().then((answer) => parent.postMessage(Notification.permission + answer, '*'))"
        let frame = "<script>\(request);</script>"
        let encoded = try #require(frame.addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let head = "<script>window.addEventListener('message', (event) => { window.frameAnswer = event.data; });</script>"
        let tab = try await open(head: head, body: "<iframe src='data:text/html,\(encoded)'></iframe>")
        try await waitUntilTrue("return window.frameAnswer === 'denieddenied'", in: tab)

        let insecure = try await open(address: "http://notify.example.com/")
        #expect(try await evaluate("return Notification.permission", in: insecure) as? String == "denied")
        _ = try await evaluate("Notification.requestPermission().then((answer) => { window.answer = answer; }); return true", in: insecure)
        try await waitUntilTrue("return window.answer === 'denied'", in: insecure)
        #expect(tab.permissionPrompts.current == nil && insecure.permissionPrompts.current == nil)
    }
}

/// macOS's notifications, kept in memory.
@MainActor
private final class FakeSystemNotifications: SystemNotifications {
    var onActivate: (@MainActor (String) -> Void)?
    private(set) var added: [SystemNotification] = []
    private(set) var removed: [String] = []
    private(set) var authorizationRequests = 0

    func requestAuthorization() async -> Bool {
        authorizationRequests += 1
        return true
    }

    func add(_ notification: SystemNotification) async throws {
        added.append(notification)
    }

    func removeDelivered(_ identifiers: [String]) {
        removed += identifiers
    }
}

@MainActor
private final class FakeNotificationRevealer: PageNotificationRevealing {
    private(set) var revealed: [BrowserTab] = []

    func reveal(_ page: BrowserTab) {
        revealed.append(page)
    }
}
