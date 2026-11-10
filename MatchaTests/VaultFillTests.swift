import Foundation
@testable import Matcha
import Testing
import WebKit

/// The vault's filling in a real page (`VAULT.md` § 8.3): the script of its own world reports the login form, fills
/// only when called, and only for the origin expected; a sent form is offered for saving, never in a private window.
@MainActor
@Suite(.webKit)
struct VaultFillTests {
    private let session: BrowserSession
    private let window = AudioTestWindow()

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
    }

    private static let form = [
        #"<form id="login" onsubmit="event.preventDefault()">"#,
        #"<input id="user" type="email" autocomplete="username">"#,
        #"<input id="pass" type="password" autocomplete="current-password">"#,
        #"<button id="send" type="submit">Sign in</button></form>"#,
    ].joined()

    private func open(body: String, address: String = "https://accounts.example.com/login") async throws -> BrowserTab {
        let manager = session.spaces[0].tabManager
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        window.show(tab.loadedWebView)
        try await load(body, title: "vault", address: address, in: tab)
        return tab
    }

    private func load(
        _ body: String,
        title: String,
        address: String = "https://accounts.example.com/login",
        in tab: BrowserTab,
    ) async throws {
        tab.loadedWebView.loadHTMLString(
            "<html><head><title>\(title)</title></head><body>\(body)</body></html>",
            baseURL: URL(string: address),
        )
        try await waitUntil { tab.title == title && !tab.isLoading }
    }

    private func value(of id: String, in tab: BrowserTab) async throws -> String? {
        try await tab.loadedWebView.callAsyncJavaScript(
            "return document.getElementById(id).value",
            arguments: ["id": id],
            contentWorld: .page,
        ) as? String
    }

    @Test func `the form is reported, then filled only for its own origin`() async throws {
        let tab = try await open(body: Self.form)
        try await waitUntil { tab.vaultForms.hasLoginForm }
        let frame = try #require(tab.vaultForms.fillableFrames.first)
        #expect(frame.origin == "https://accounts.example.com")
        #expect(frame.isMainFrame)

        // Another origin expected: the script refuses.
        let other = VaultPageForms.Frame(
            info: frame.info, origin: "https://evil.example", url: frame.url, isMainFrame: true,
            hasPassword: true, hasUsername: false, isSignup: false,
        )
        #expect(await !VaultFiller.fill(other, in: tab.loadedWebView, username: "jeremy", password: "secret"))
        #expect(try await value(of: "pass", in: tab)?.isEmpty == true)

        #expect(await VaultFiller.fill(frame, in: tab.loadedWebView, username: "jeremy@example.com", password: "secret"))
        #expect(try await value(of: "user", in: tab) == "jeremy@example.com")
        #expect(try await value(of: "pass", in: tab) == "secret")
    }

    @Test func `the page doesn't see the script of the vault`() async throws {
        let tab = try await open(body: Self.form)
        try await waitUntil { tab.vaultForms.hasLoginForm }
        let seen = try await tab.loadedWebView.callAsyncJavaScript("return typeof window.__matchaVaultFill", contentWorld: .page)
        #expect(seen as? String == "undefined")
    }

    private func send(_ tab: BrowserTab) async throws {
        _ = try await tab.loadedWebView.callAsyncJavaScript(
            "document.getElementById('user').value = 'jeremy'; document.getElementById('pass').value = 'typed';"
                + "document.getElementById('send').click();",
            contentWorld: .page,
        )
    }

    @Test func `a sent form is offered for saving, never in a private window`() async throws {
        let tab = try await open(body: Self.form)
        try await waitUntil { tab.vaultForms.hasLoginForm }
        // The test pages keep nothing (a non-persistent store): a private window.
        #expect(tab.vaultForms.isPrivate)
        try await send(tab)
        try await Task.sleep(for: .milliseconds(500))
        #expect(tab.vaultForms.offer == nil)

        tab.vaultForms.isPrivate = false
        try await send(tab)
        try await waitUntil { tab.vaultForms.offer != nil }
        #expect(tab.vaultForms.offer?.username == "jeremy")
        #expect(tab.vaultForms.offer?.password == "typed")
        #expect(tab.vaultForms.offer?.url.host() == "accounts.example.com")
    }

    @Test func `a page cut off from the filling reports nothing, until connected again`() async throws {
        let tab = try await open(body: Self.form)
        try await waitUntil { tab.vaultForms.hasLoginForm }
        let controller = tab.loadedWebView.configuration.userContentController
        tab.vaultForms.isPrivate = false

        // The vault turned off: from the next load, the script stops as soon as it starts.
        VaultFillScript.setEnabled(false, in: controller)
        try await load(Self.form, title: "off", in: tab)
        try await send(tab)
        try await Task.sleep(for: .milliseconds(500))
        #expect(!tab.vaultForms.hasLoginForm)
        #expect(tab.vaultForms.offer == nil)

        VaultFillScript.setEnabled(true, in: controller)
        try await load(Self.form, title: "on", in: tab)
        try await waitUntil { tab.vaultForms.hasLoginForm }
    }

    @Test func `the password check finds weak, reused and insecure logins`() {
        let (weak, reusedA, reusedB, fine) = (UUID(), UUID(), UUID(), UUID())
        let report = VaultSecurityReport([
            .init(id: weak, password: "matcha", urls: ["http://example.com"]),
            .init(id: reusedA, password: "correct-horse-battery-staple-42", urls: ["https://a.example"]),
            .init(id: reusedB, password: "correct-horse-battery-staple-42", urls: ["https://b.example"]),
            .init(id: fine, password: "k7#Qp9!vZ2@mW4$xR8&n", urls: ["https://c.example"]),
        ])
        #expect(report.issues[weak] == [.weak, .insecure])
        #expect(report.issues[reusedA] == [.reused])
        #expect(report.issues[reusedB] == [.reused])
        #expect(report.issues[fine] == nil)
    }
}
