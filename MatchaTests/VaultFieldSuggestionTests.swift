import AppKit
import Foundation
@testable import Matcha
import Testing
import WebKit

/// The native list under a login field (`VAULT.md` § 8.1): the script reports the field the user reached with a real
/// click, never one the page focused alone nor a field that isn't a login's; typing withdraws it; while the list has
/// rows, the arrows and Return go to it, not to the page.
@MainActor
@Suite(.webKit)
struct VaultFieldSuggestionTests {
    private let session: BrowserSession
    private let window = AudioTestWindow()

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
    }

    private static func field(_ id: String, _ attributes: String, left: Int, top: Int) -> String {
        #"<input id="\#(id)" \#(attributes) style="position:absolute;left:\#(left)px;top:\#(top)px;width:200px;height:24px">"#
    }

    private static let form = [
        #"<form onsubmit="event.preventDefault()">"#,
        field("search", #"type="text" placeholder="Search""#, left: 10, top: 10),
        field("user", #"type="email" autocomplete="username""#, left: 40, top: 60),
        field("pass", #"type="password""#, left: 40, top: 100),
        "</form>",
    ].joined()

    private func open(_ body: String, waitsForForm: Bool = true) async throws -> BrowserTab {
        let tab = session.spaces[0].tabManager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        window.show(tab.loadedWebView)
        tab.loadedWebView.loadHTMLString(
            "<html><head><title>login</title></head><body style=\"margin:0\">\(body)</body></html>",
            baseURL: URL(string: "https://accounts.example.com/login"),
        )
        try await waitUntil { tab.title == "login" && !tab.isLoading }
        if waitsForForm {
            try await waitUntil { tab.vaultForms.hasLoginForm }
        }
        return tab
    }

    /// A real click (the page can't make one) in the middle of the element `id`, given to the web view itself: a
    /// window off screen doesn't always route the events it is sent.
    private func click(_ id: String, in tab: BrowserTab) async throws {
        let webView = tab.loadedWebView
        let box = try #require(try await webView.callAsyncJavaScript(
            "const box = document.getElementById(id).getBoundingClientRect();"
                + "return [box.left + box.width / 2, box.top + box.height / 2, window.innerWidth];",
            arguments: ["id": id],
            contentWorld: .page,
        ) as? [Double])
        let scale = webView.bounds.width / box[2]
        let window = try #require(webView.window)
        let point = webView.convert(NSPoint(x: box[0] * scale, y: box[1] * scale), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1,
            ))
            if type == .leftMouseDown {
                webView.mouseDown(with: event)
            } else {
                webView.mouseUp(with: event)
            }
        }
    }

    /// A real key, given to the web view.
    private func press(_ characters: String, keyCode: UInt16, in tab: BrowserTab) throws {
        let webView = tab.loadedWebView
        let window = try #require(webView.window)
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = try #require(NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters,
                isARepeat: false, keyCode: keyCode,
            ))
            if type == .keyDown {
                webView.keyDown(with: event)
            } else {
                webView.keyUp(with: event)
            }
        }
    }

    @Test func `a click in a login field places the list under it, and typing withdraws it`() async throws {
        let tab = try await open(Self.form)
        try await click("user", in: tab)
        try await waitUntil { tab.vaultForms.focusedField != nil }
        let place = try #require(tab.vaultForms.focusedField)
        #expect(place.left == 40 && place.top == 60 && place.width == 200 && place.height == 24)
        let box = VaultSuggestionPlacement.fieldBox(place, in: tab.loadedWebView.bounds.size)
        #expect(box == CGRect(x: 40, y: 60, width: 200, height: 24))

        // Typing withdraws it; Tab to the password brings it under that field.
        try press("j", keyCode: 38, in: tab)
        try await waitUntil { tab.vaultForms.focusedField == nil }
        try press("\t", keyCode: 48, in: tab)
        try await waitUntil { tab.vaultForms.focusedField?.top == 100 }
    }

    @Test func `a login dialog opened by a click shows the list under its user name field`() async throws {
        // As Twitch: “Log In” opens a dialog whose lone user name field takes the focus.
        let tab = try await open([
            #"<button id="login" style="position:absolute;left:10px;top:10px;width:100px;height:30px">Log In</button>"#,
            #"<div id="dialog" hidden>"#,
            Self.field("user", #"type="text" autocomplete="username""#, left: 40, top: 120),
            "</div><script>document.getElementById('login').addEventListener('click', () => {",
            "document.getElementById('dialog').hidden = false;",
            "setTimeout(() => document.getElementById('user').focus(), 50); });</script>",
        ].joined(), waitsForForm: false)
        try await click("login", in: tab)
        try await waitUntil { tab.vaultForms.focusedField?.top == 120 }
        try await waitUntil { tab.vaultForms.mainFrame?.hasUsername == true }
    }

    @Test func `neither a focus the page gives alone nor a field that isn't a login's shows the list`() async throws {
        let tab = try await open(Self.form + "<script>setTimeout(() => document.getElementById('user').focus(), 200)</script>")
        try await Task.sleep(for: .milliseconds(800))
        #expect(try await tab.loadedWebView
            .callAsyncJavaScript("return document.activeElement.id", contentWorld: .page) as? String == "user")
        #expect(tab.vaultForms.focusedField == nil)

        try await click("search", in: tab)
        try await Task.sleep(for: .milliseconds(600))
        #expect(tab.vaultForms.focusedField == nil)
    }

    @Test func `while the list has rows, the arrows and Return move in it, not in the page`() async throws {
        let tab = try await open(Self
            .form + "<script>window.keys = []; document.addEventListener('keydown', (e) => keys.push(e.key));</script>")
        try await click("user", in: tab)
        try await waitUntil { tab.vaultForms.focusedField != nil }
        // The rows the list gives when it shows two logins.
        var chosen: [Int] = []
        tab.vaultForms.suggestionRows = .init(owner: UUID(), count: 2) { chosen.append($0) }
        try press("\u{F701}", keyCode: 125, in: tab)
        try press("\u{F701}", keyCode: 125, in: tab)
        #expect(tab.vaultForms.highlightedRow == 1)
        try press("\r", keyCode: 36, in: tab)
        #expect(chosen == [1])

        // Without rows, the page gets its keys again.
        tab.vaultForms.suggestionRows = nil
        try press("\u{F701}", keyCode: 125, in: tab)
        // WebKit hands keys to the page later: the first one it gets is this one, not those the list took.
        var keys: [String] = []
        try await waitUntilAsync {
            keys = try await tab.loadedWebView.callAsyncJavaScript("return keys", contentWorld: .page) as? [String] ?? []
            return !keys.isEmpty
        }
        #expect(keys == ["ArrowDown"])
    }
}

/// Where the list goes, what the script may send, and how the keyboard moves in the list (`VAULT.md` § 8.1).
struct VaultSuggestionPlacementTests {
    private let size = CGSize(width: 800, height: 600)

    @Test func `the field's box follows the page's zoom, and nothing shows for a field out of sight`() {
        let zoomed = VaultFieldPlace(left: 100, top: 50, width: 200, height: 30, viewportWidth: 600, viewportHeight: 400)
        #expect(VaultSuggestionPlacement.fieldBox(zoomed, in: CGSize(width: 900, height: 600)) == CGRect(
            x: 150,
            y: 75,
            width: 300,
            height: 45,
        ))
        let above = VaultFieldPlace(left: 100, top: -100, width: 200, height: 30, viewportWidth: 800, viewportHeight: 600)
        #expect(VaultSuggestionPlacement.fieldBox(above, in: size) == nil)
    }

    @Test func `the list goes under the field, above it when only there it fits, and stays in the page`() {
        let field = CGRect(x: 100, y: 100, width: 200, height: 30)
        #expect(VaultSuggestionPlacement.listFrame(for: field, height: 120, in: size) == CGRect(x: 100, y: 134, width: 260, height: 120))
        let low = CGRect(x: 100, y: 540, width: 200, height: 30)
        #expect(VaultSuggestionPlacement.listFrame(for: low, height: 120, in: size).minY == 416)
        let right = CGRect(x: 700, y: 100, width: 100, height: 30)
        #expect(VaultSuggestionPlacement.listFrame(for: right, height: 120, in: size).minX == 532)
        let narrow = VaultSuggestionPlacement.listFrame(for: field, height: 120, in: CGSize(width: 200, height: 600))
        #expect(narrow.minX == 8 && narrow.width == 184)
    }

    @MainActor
    @Test func `the keyboard moves in the rows, fills the highlighted one, and lets the rest through`() {
        let forms = VaultPageForms()
        var chosen: [Int] = []
        #expect(!forms.takeSuggestionKey(.next))
        forms.focusedField = VaultFieldPlace(left: 0, top: 0, width: 100, height: 20, viewportWidth: 800, viewportHeight: 600)
        // Shown, but without rows (no login for the site): the page keeps its keys.
        #expect(!forms.takeSuggestionKey(.next))
        forms.suggestionRows = .init(owner: UUID(), count: 3) { chosen.append($0) }
        // ↩ before any row is highlighted sends the form.
        #expect(!forms.takeSuggestionKey(.choose))
        #expect(forms.takeSuggestionKey(.previous))
        #expect(forms.highlightedRow == 2)
        #expect(forms.takeSuggestionKey(.next))
        #expect(forms.highlightedRow == 2)
        #expect(forms.takeSuggestionKey(.previous) && forms.takeSuggestionKey(.previous) && forms.takeSuggestionKey(.previous))
        #expect(forms.highlightedRow == 0)
        #expect(forms.takeSuggestionKey(.choose))
        #expect(chosen == [0])
        #expect(forms.takeSuggestionKey(.close))
        #expect(forms.focusedField == nil)
        #expect(!forms.takeSuggestionKey(.next))
    }

    @Test func `a field message needs every number, finite, and a viewport`() {
        let body: [String: Any] = ["type": "field", "x": 1, "y": 2, "width": 3, "height": 4, "viewportWidth": 800, "viewportHeight": 600]
        #expect(VaultFormMessage(body: body) == .field(VaultFieldPlace(
            left: 1, top: 2, width: 3, height: 4, viewportWidth: 800, viewportHeight: 600,
        )))
        #expect(VaultFormMessage(body: body.merging(["viewportWidth": 0]) { $1 }) == nil)
        #expect(VaultFormMessage(body: body.merging(["x": Double.nan]) { $1 }) == nil)
        #expect(VaultFormMessage(body: body.filter { $0.key != "height" }) == nil)
        #expect(VaultFormMessage(body: ["type": "fieldDone"]) == .fieldDone)
    }
}
