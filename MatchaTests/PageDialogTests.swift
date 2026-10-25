import AppKit
@testable import Matcha
import Testing
import WebKit

/// What a page asks the user directly (audits K1 to K3): JavaScript dialogs, files to send, a login.
@MainActor
@Suite(.webKit)
struct PageDialogTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())
    private let dialogs = FakePageDialogs()

    init() {
        manager.coordinator.dialogs = dialogs
    }

    @Test func `confirm and prompt get the user's answer`() async throws {
        let page = try await openPage()
        dialogs.answer = { _ in PageDialogAnswer(isConfirmed: true, text: "Grace") }

        #expect(try await page.loadedWebView.evaluateJavaScript("confirm('Supprimer ce message ?')") as? Bool == true)
        #expect(try await page.loadedWebView.evaluateJavaScript("prompt('Nom ?', 'Ada')") as? String == "Grace")
        #expect(dialogs.shown.map(\.kind) == [.confirm, .prompt(defaultText: "Ada")])
        #expect(dialogs.shown.first?.message == "Supprimer ce message ?")
        #expect(dialogs.shown.first?.site == "obtest://pages")

        dialogs.answer = { _ in PageDialogAnswer(isConfirmed: false) }
        #expect(try await page.loadedWebView.evaluateJavaScript("confirm('Encore ?')") as? Bool == false)
        #expect(try await page.loadedWebView.evaluateJavaScript("prompt('Nom ?') === null") as? Bool == true)
    }

    @Test func `the user can stop a page's dialogs until its next document`() async throws {
        let page = try await openPage()
        dialogs.answer = { PageDialogAnswer(isConfirmed: true, suppressesFurther: $0.offersSuppression) }

        _ = try await page.loadedWebView.evaluateJavaScript("alert('un'); true")
        _ = try await page.loadedWebView.evaluateJavaScript("alert('deux'); true")
        #expect(dialogs.shown.map(\.offersSuppression) == [false, true])

        // Stopped: not shown, and “Cancel”.
        #expect(try await page.loadedWebView.evaluateJavaScript("confirm('trois')") as? Bool == false)
        #expect(dialogs.shown.count == 2)

        page.load(TestPages.url("suite"))
        try await waitUntil { page.title == "suite" && !page.isLoading }
        _ = try await page.loadedWebView.evaluateJavaScript("alert('quatre'); true")
        #expect(dialogs.shown.count == 3)
    }

    @Test func `a long message is cut`() {
        let dialog = PageDialog(kind: .alert, message: String(repeating: "a", count: 5000), site: nil, offersSuppression: false)
        #expect(dialog.message.count == PageDialog.maximumLength + 1)
        // Review WB18: a prompt's default text too.
        let prompt = PageDialog(
            kind: .prompt(defaultText: String(repeating: "x", count: 50000)),
            message: "",
            site: nil,
            offersSuppression: false,
        )
        #expect(prompt.kind == .prompt(defaultText: String(repeating: "x", count: PageDialog.maximumLength)))
    }

    /// Review WB7: a frame without a website (`data:`, sandboxed) never passes for the page itself.
    @Test func `a dialog of a frame without a website says it is embedded`() async throws {
        let frame = try #require("<script>alert('session expirée')</script>".addingPercentEncoding(withAllowedCharacters: .alphanumerics))
        let page = try await openPage(body: "<iframe src='data:text/html,\(frame)'></iframe>")
        try await waitUntil { !dialogs.shown.isEmpty }
        #expect(dialogs.shown.first?.site == nil)
        #expect(dialogs.shown.first?.isFromEmbeddedFrame == true)
        _ = try await page.loadedWebView.evaluateJavaScript("alert('page'); true")
        #expect(dialogs.shown.last?.isFromEmbeddedFrame == false)
    }

    @Test func `a file input gets the files the user chose`() async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "envoi-\(UUID().uuidString).txt")
        try Data("bonjour".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        dialogs.files = [file]
        let input = "<input type='file' id='f' onchange=\"document.title = this.files.length + ':' + this.files[0].name\">"
        let page = try await openPage(body: input)

        _ = try await page.loadedWebView.evaluateJavaScript("document.getElementById('f').click(); true")
        // A quarter of a second alone, but up to tens of seconds under the load of the whole suite.
        try await waitUntil(timeout: .seconds(60)) { page.title == "1:\(file.lastPathComponent)" }
    }

    /// Review IU15: a sheet on screen ends, without an answer, when its document changes or its page goes.
    @Test func `a sheet ends with its document`() async throws {
        let state = PageDialogState()
        let answer = Task {
            await state.present { () async -> Int? in
                try? await Task.sleep(for: .seconds(60))
                return Task.isCancelled ? nil : 1
            }
        }
        try await waitUntil { state.hasSheetOnScreen }
        state.documentDidChange()
        #expect(await answer.value == nil)
        #expect(!state.hasSheetOnScreen)
    }

    @Test func `a website's login is asked for, certificates are left to the system`() async throws {
        let page = try await openPage()
        let basic = challenge(method: NSURLAuthenticationMethodHTTPBasic, previousFailures: 1)
        dialogs.credential = URLCredential(user: "ada", password: "secret", persistence: .forSession)

        let (disposition, credential) = await manager.coordinator.webView(page.loadedWebView, respondTo: basic)
        #expect(disposition == .useCredential)
        #expect(credential?.user == "ada")
        #expect(dialogs.logins == [LoginRequest(
            site: "http://pages",
            realm: "Administration",
            isSecure: false,
            failedBefore: true,
            user: nil,
        )])

        dialogs.credential = nil
        #expect(await manager.coordinator.webView(page.loadedWebView, respondTo: basic).0 == .rejectProtectionSpace)

        let trust = challenge(method: NSURLAuthenticationMethodServerTrust)
        #expect(await manager.coordinator.webView(page.loadedWebView, respondTo: trust).0 == .performDefaultHandling)
        #expect(dialogs.logins.count == 2)
    }

    /// Review WB6: an image or a frame of another site gets no sheet; Kerberos lets the system sign in first (WB16).
    @Test func `only the page's website may ask, and Kerberos tries the system first`() async throws {
        let page = try await openPage()
        dialogs.credential = URLCredential(user: "ada", password: "secret", persistence: .forSession)
        let other = challenge(method: NSURLAuthenticationMethodHTTPBasic, host: "evil.example")
        #expect(await manager.coordinator.webView(page.loadedWebView, respondTo: other).0 == .performDefaultHandling)
        let kerberos = challenge(method: NSURLAuthenticationMethodNegotiate)
        #expect(await manager.coordinator.webView(page.loadedWebView, respondTo: kerberos).0 == .performDefaultHandling)
        #expect(dialogs.logins.isEmpty)

        let failed = challenge(method: NSURLAuthenticationMethodNegotiate, previousFailures: 1)
        #expect(await manager.coordinator.webView(page.loadedWebView, respondTo: failed).0 == .useCredential)
        #expect(dialogs.logins.count == 1)
    }

    /// Review WB6: one sheet at a time per protected area, and the user can stop them.
    @Test func `a burst of challenges shows one sheet, and the user can stop them`() async throws {
        let page = try await openPage()
        dialogs.credential = URLCredential(user: "ada", password: "secret", persistence: .forSession)
        dialogs.holdsLogins = true
        let basic = challenge(method: NSURLAuthenticationMethodHTTPBasic)
        let coordinator = manager.coordinator
        let webView = page.loadedWebView
        let answers = (0 ..< 5).map { _ in Task { await coordinator.webView(webView, respondTo: basic).1?.user } }
        try await waitUntil { dialogs.logins.count == 1 }
        dialogs.releaseLogins()
        for answer in answers {
            #expect(await answer.value == "ada")
        }
        #expect(dialogs.logins.map(\.offersSuppression) == [false])

        dialogs.holdsLogins = false
        dialogs.suppressesFurther = true
        _ = await coordinator.webView(webView, respondTo: basic)
        #expect(dialogs.logins.map(\.offersSuppression) == [false, true])
        #expect(await coordinator.webView(webView, respondTo: basic).0 == .performDefaultHandling)
        #expect(dialogs.logins.count == 2)
    }

    private func openPage(body: String = "") async throws -> BrowserTab {
        let page = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        page.load(TestPages.url("page", body: body))
        try await waitUntil { page.title == "page" && !page.isLoading }
        return page
    }

    /// A challenge from `host`: by default, that of the pages of `TestPages`.
    private func challenge(method: String, previousFailures: Int = 0, host: String = "pages") -> URLAuthenticationChallenge {
        let space = URLProtectionSpace(
            host: host,
            port: 80,
            protocol: "http",
            realm: "Administration",
            authenticationMethod: method,
        )
        return URLAuthenticationChallenge(
            protectionSpace: space,
            proposedCredential: nil,
            previousFailureCount: previousFailures,
            failureResponse: nil,
            error: nil,
            sender: ChallengeSender(),
        )
    }
}

/// Dialogs answered by the test.
@MainActor
final class FakePageDialogs: PageDialogPresenting {
    var shown: [PageDialog] = []
    var answer: (PageDialog) -> PageDialogAnswer? = { _ in PageDialogAnswer(isConfirmed: true) }
    var files: [URL]?
    var logins: [LoginRequest] = []
    var credential: URLCredential?
    var suppressesFurther = false
    /// The login sheets wait for `releaseLogins()`.
    var holdsLogins = false
    private var heldLogins: [CheckedContinuation<Void, Never>] = []

    func releaseLogins() {
        heldLogins.forEach { $0.resume() }
        heldLogins = []
    }

    func present(_ dialog: PageDialog, for _: WKWebView) async -> PageDialogAnswer? {
        shown.append(dialog)
        return answer(dialog)
    }

    func chooseFiles(allowsMultipleSelection _: Bool, allowsDirectories _: Bool, for _: WKWebView) async -> [URL]? {
        files
    }

    func credential(for login: LoginRequest, for _: WKWebView) async -> LoginAnswer? {
        logins.append(login)
        if holdsLogins {
            await withCheckedContinuation { heldLogins.append($0) }
        }
        return LoginAnswer(credential: credential, suppressesFurther: suppressesFurther)
    }

    func save(_: BrowserTab) {}

    func print(_: BrowserTab) {}
}

/// Sender of a challenge built by hand: the answer goes through the delegate's return value.
private final class ChallengeSender: NSObject, URLAuthenticationChallengeSender {
    func use(_: URLCredential, for _: URLAuthenticationChallenge) {}
    func continueWithoutCredential(for _: URLAuthenticationChallenge) {}
    func cancel(_: URLAuthenticationChallenge) {}
}
