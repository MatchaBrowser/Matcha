import AppKit
@testable import Matcha
import Testing
import WebKit

/// Links to other apps (audit W2): nothing opens without the user. Every link to another app waits in the page's
/// banner, which names the app; “Always Open” is remembered for the website and that kind of link.
@MainActor
struct ExternalAppTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())

    @Test func `a page can't pile up the same request, and a new document drops them`() {
        let prompts = PermissionPromptQueue()
        var opened = 0
        let zoom = request(.openApp(scheme: "zoommtg")) { opened += 1 }
        #expect(prompts.enqueue(zoom))
        #expect(!prompts.enqueue(request(.openApp(scheme: "zoommtg")) { opened += 10 }))
        #expect(prompts.enqueue(request(.openApp(scheme: "mailto")) { opened += 100 }))
        #expect(prompts.hasPending)

        prompts.answerAction(.allowOnce)
        #expect(opened == 1)
        prompts.answerAction(.decline)
        #expect(opened == 1)
        #expect(!prompts.hasPending)

        prompts.enqueue(zoom)
        prompts.denyAll()
        #expect(prompts.currentAction == nil)
        #expect(opened == 1)
    }

    @Test func `a click on a mail link asks too`() async throws {
        let (page, opened) = try await openPage(body: "<a id='l' href='mailto:moi@example.com'>courriel</a>")

        try await click("l", in: page)
        try await waitUntil { page.permissionPrompts.currentAction != nil }
        #expect(opened.urls.isEmpty)
        #expect(page.permissionPrompts.currentAction?.appName == "Mail")
        #expect(page.permissionPrompts.currentAction?.action == .openApp(scheme: "mailto"))

        page.permissionPrompts.answerAction(.allowOnce)
        #expect(try opened.urls == [#require(URL(string: "mailto:moi@example.com"))])
    }

    @Test func `always open is remembered for the website and that kind of link only`() async throws {
        let store = SitePermissionStore(context: nil)
        manager.sitePermissions = SitePermissionScope(store: store, profileID: nil)
        let body = "<a id='zoom' href='zoommtg://zoom.us/join'>réunion</a><a id='mail' href='mailto:moi@example.com'>courriel</a>"
        let (page, opened) = try await openPage(body: body)

        try await click("zoom", in: page)
        try await waitUntil { page.permissionPrompts.currentAction != nil }
        #expect(page.permissionPrompts.currentAction?.canRemember == true)
        page.permissionPrompts.answerAction(.alwaysAllow)
        #expect(opened.urls.count == 1)

        // Zoom again: opened without asking.
        try await click("zoom", in: page)
        try await waitUntil { opened.urls.count == 2 }
        #expect(page.permissionPrompts.currentAction == nil)

        // Another kind of link from the same website still asks.
        try await click("mail", in: page)
        try await waitUntil { page.permissionPrompts.currentAction != nil }
        #expect(opened.urls.count == 2)
        #expect(store.actions.entries.map(\.action) == [.openApp(scheme: "zoommtg")])
    }

    @Test func `a script can't open an app on its own`() async throws {
        let (page, opened) = try await openPage(body: "<script>location.href = 'mailto:moi@example.com'</script>")

        try await waitUntil { page.permissionPrompts.currentAction != nil }
        page.permissionPrompts.answerAction(.decline)
        #expect(opened.urls.isEmpty)
        #expect(manager.tabs.count == 1)
    }

    @Test func `a script run by a click on a button asks too`() async throws {
        let button = "<button id='b' onclick=\"location.href = 'mailto:moi@example.com'\">courriel</button>"
        let (page, opened) = try await openPage(body: button)

        try await click("b", in: page)
        try await waitUntil { page.permissionPrompts.currentAction != nil || !opened.urls.isEmpty }
        #expect(opened.urls.isEmpty)
    }

    @Test func `a link no app handles does nothing`() async throws {
        let (page, opened) = try await openPage(body: "", handler: nil)

        let recorder = PolicyRecorder()
        let action = try FakeNavigationAction(url: #require(URL(string: "inconnu-matcha://y")), modifierFlags: [])
        manager.coordinator.webView(page.loadedWebView, decidePolicyFor: action, decisionHandler: recorder.record)
        #expect(recorder.policies == [.cancel])
        #expect(page.permissionPrompts.currentAction == nil)
        #expect(opened.urls.isEmpty)
    }

    private static let mail = URL(filePath: "/System/Applications/Mail.app")

    /// Opened links, recorded instead of being handed to another app.
    private final class Opened {
        var urls: [URL] = []
    }

    private func request(_ action: SiteAction, perform: @escaping @MainActor () -> Void) -> SiteActionRequest {
        SiteActionRequest(action: action, origin: nil, scope: nil, appName: "Zoom", appIcon: NSImage(), perform: perform)
    }

    private func click(_ id: String, in page: BrowserTab) async throws {
        _ = try await page.loadedWebView.evaluateJavaScript("document.getElementById('\(id)').click(); true")
    }

    /// Page with `body`; links open in `handler` (none: no app handles them).
    private func openPage(body: String, handler: URL? = Self.mail) async throws -> (BrowserTab, Opened) {
        let opened = Opened()
        manager.coordinator.openExternally = { opened.urls.append($0)
            return true
        }
        manager.coordinator.applicationForURL = { _ in handler }
        let page = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        page.load(TestPages.url("ouvrant", body: body))
        try await waitUntil { page.title == "ouvrant" && !page.isLoading }
        return (page, opened)
    }
}
