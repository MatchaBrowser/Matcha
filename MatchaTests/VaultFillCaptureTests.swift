import Foundation
@testable import Matcha
import Testing
import WebKit

/// The vault's script on login pages that don't post a plain form (`VAULT.md` § 8.3, § 8.4): fields inside Web
/// Components (open shadow roots), a login sent by a script's button and offered only once it succeeds, and a login in
/// two steps whose user name is typed on the page before the password's.
@MainActor
@Suite(.webKit)
struct VaultFillCaptureTests {
    private let session: BrowserSession
    private let window = AudioTestWindow()

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
    }

    private func open(_ body: String) async throws -> BrowserTab {
        let tab = session.spaces[0].tabManager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        window.show(tab.loadedWebView)
        try await load(body, title: "first", in: tab)
        // Saving is offered outside private windows only; the test pages' store keeps nothing, like a private one.
        tab.vaultForms.isPrivate = false
        return tab
    }

    private func load(_ body: String, title: String, in tab: BrowserTab) async throws {
        tab.loadedWebView.loadHTMLString(
            "<html><head><title>\(title)</title></head><body>\(body)</body></html>",
            baseURL: URL(string: "https://accounts.example.com/login"),
        )
        try await waitUntil { tab.title == title && !tab.isLoading }
    }

    @discardableResult
    private func run(_ script: String, in tab: BrowserTab) async throws -> Any? {
        try await tab.loadedWebView.callAsyncJavaScript(script, contentWorld: .page)
    }

    /// A component whose fields are in its shadow root, and a “button” that is a `div`: the login succeeds (the field
    /// goes away) only once `window.accepts` is true.
    private static let component = [
        #"<div id="host"></div><script>"#,
        #"const root = document.getElementById('host').attachShadow({ mode: 'open' });"#,
        #"root.innerHTML = '<input id="user" type="text" name="username"><input id="pass" type="password">"#,
        #"<div role="button" id="go">Log in</div>';"#,
        #"root.getElementById('go').addEventListener('click', () => {"#,
        #"if (window.accepts) { root.getElementById('pass').style.display = 'none'; } });"#,
        "</script>",
    ].joined()

    private static let shadowField = "document.getElementById('host').shadowRoot.getElementById(id)"

    @Test func `fields inside a component are found, filled, and their login offered once it succeeds`() async throws {
        let tab = try await open(Self.component)
        try await waitUntil { tab.vaultForms.hasLoginForm }
        let frame = try #require(tab.vaultForms.fillableFrames.first)
        #expect(await VaultFiller.fill(frame, in: tab.loadedWebView, username: "jeremy@example.com", password: "secret"))
        #expect(try await value(of: "user", in: tab) == "jeremy@example.com")
        #expect(try await value(of: "pass", in: tab) == "secret")

        // Refused: the password stays in its field, nothing is offered.
        try await run("\(Self.shadowField).click()", in: tab, id: "go")
        try await Task.sleep(for: .milliseconds(1200))
        #expect(tab.vaultForms.offer == nil)

        try await run("window.accepts = true; \(Self.shadowField).click()", in: tab, id: "go")
        try await waitUntil { tab.vaultForms.offer != nil }
        #expect(tab.vaultForms.offer?.username == "jeremy@example.com")
        #expect(tab.vaultForms.offer?.password == "secret")
    }

    private func run(_ script: String, in tab: BrowserTab, id: String) async throws {
        _ = try await tab.loadedWebView.callAsyncJavaScript(script, arguments: ["id": id], contentWorld: .page)
    }

    private func value(of id: String, in tab: BrowserTab) async throws -> String? {
        try await tab.loadedWebView.callAsyncJavaScript("return \(Self.shadowField).value", arguments: ["id": id], contentWorld: .page)
            as? String
    }

    @Test func `the user name of a first step goes with the password of the next page`() async throws {
        // The first step, as Apple's: a lone field named after the account, no password.
        let tab = try await open(
            #"<form onsubmit="event.preventDefault()"><input id="account_name_text_field" type="text">"#
                + #"<button id="next" type="submit">Continue</button></form>"#,
        )
        try await waitUntil { tab.vaultForms.hasLoginForm }
        #expect(tab.vaultForms.fillableFrames.first?.hasUsername == true)
        try await run(
            "document.getElementById('account_name_text_field').value = 'jeremy@example.com';"
                + "document.getElementById('next').click();",
            in: tab,
        )

        try await load(
            #"<form onsubmit="event.preventDefault()"><input id="pass" type="password">"#
                + #"<button id="send" type="submit">Sign in</button></form>"#,
            title: "second",
            in: tab,
        )
        try await waitUntil { tab.vaultForms.hasLoginForm }
        try await run("document.getElementById('pass').value = 'typed'; document.getElementById('send').click();", in: tab)
        try await waitUntil { tab.vaultForms.offer != nil }
        #expect(tab.vaultForms.offer?.username == "jeremy@example.com")
        #expect(tab.vaultForms.offer?.password == "typed")
    }
}
