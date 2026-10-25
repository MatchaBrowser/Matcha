import Foundation
import WebKit

/// What a page asks the user directly (audits K1 to K3): a JavaScript dialog (`alert`, `confirm`, `prompt`), files to
/// send, a user name and password; and the panels of its menu, saving and printing. WebKit answers “Cancel” to all of
/// them when the app doesn't show them. Shown by `SystemPageDialogs` (interface, given by the app: audit C1), as
/// sheets on the page's window; replaced in tests.
@MainActor
protocol PageDialogPresenting: AnyObject {
    /// nil if it couldn't be shown (page in no visible window): the page gets “Cancel”.
    func present(_ dialog: PageDialog, for webView: WKWebView) async -> PageDialogAnswer?
    /// Files chosen by the user for an `<input type="file">`; nil: none.
    func chooseFiles(allowsMultipleSelection: Bool, allowsDirectories: Bool, for webView: WKWebView) async -> [URL]?
    /// User name and password typed for a website that asks for them; nil if it couldn't be shown.
    func credential(for login: LoginRequest, for webView: WKWebView) async -> LoginAnswer?
    /// “Save As…” for `page`.
    func save(_ page: BrowserTab)
    /// “Print…” for `page`.
    func print(_ page: BrowserTab)
}

/// No dialog can be shown (tests, a session made without interface): the page always gets “Cancel”.
@MainActor
final class UnavailablePageDialogs: PageDialogPresenting {
    func present(_: PageDialog, for _: WKWebView) async -> PageDialogAnswer? {
        nil
    }

    func chooseFiles(allowsMultipleSelection _: Bool, allowsDirectories _: Bool, for _: WKWebView) async -> [URL]? {
        nil
    }

    func credential(for _: LoginRequest, for _: WKWebView) async -> LoginAnswer? {
        nil
    }

    func save(_: BrowserTab) {}

    func print(_: BrowserTab) {}
}

/// A JavaScript dialog, as shown: its text and a `prompt`'s default text never longer than `maximumLength` (review
/// WB18), with the website of the frame that opens it.
nonisolated struct PageDialog: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case alert
        case confirm
        case prompt(defaultText: String)
    }

    static let maximumLength = 2000

    let kind: Kind
    let message: String
    /// Website of the frame that opens it; nil for a page without one (local file, or a frame with an opaque origin:
    /// `data:`, sandboxed).
    let site: String?
    /// Opened by a frame inside the page: without a website, it never passes for the page itself (review WB7).
    let isFromEmbeddedFrame: Bool
    /// “Don't allow this page to show more dialogs”, from the second dialog of a page on.
    let offersSuppression: Bool

    init(kind: Kind, message: String, site: String?, isFromEmbeddedFrame: Bool = false, offersSuppression: Bool) {
        if case let .prompt(defaultText) = kind {
            self.kind = .prompt(defaultText: Self.cut(defaultText, ellipsis: false))
        } else {
            self.kind = kind
        }
        self.message = Self.cut(message, ellipsis: true)
        self.site = site
        self.isFromEmbeddedFrame = isFromEmbeddedFrame
        self.offersSuppression = offersSuppression
    }

    /// `text` within `maximumLength`, without counting the whole of a huge one.
    private static func cut(_ text: String, ellipsis: Bool) -> String {
        let start = text.prefix(maximumLength + 1)
        guard start.count > maximumLength else {
            return text
        }
        return String(start.dropLast()) + (ellipsis ? "…" : "")
    }
}

nonisolated struct PageDialogAnswer: Equatable, Sendable {
    /// “OK” rather than “Cancel”.
    var isConfirmed: Bool
    /// Text typed in a `prompt`.
    var text: String?
    /// The page may show no more dialogs until its next document.
    var suppressesFurther = false
}

/// A website asking for a user name and password (HTTP authentication, audit K3).
nonisolated struct LoginRequest: Equatable, Sendable {
    /// The server, with its scheme if it isn't https (`http://router.local`).
    let site: String
    /// What the server calls the protected area; chosen by the server, shown as a quote.
    let realm: String?
    /// False if the password would travel unencrypted.
    let isSecure: Bool
    /// The previous attempt was refused.
    let failedBefore: Bool
    let user: String?
    /// “Don't allow this page to show more dialogs”, from the page's second dialog or sheet on (review WB6).
    var offersSuppression = false

    /// True if a sheet may ask (review WB6): only the website of the page on screen or of the page being loaded,
    /// never an image or a frame of another site (whose name and words the attacker would choose). Kerberos
    /// (`Negotiate`) first lets the system sign in alone; a sheet only once that failed (review WB16).
    static func mayAsk(method: String, failures: Int, host: String, pageHosts: [String?]) -> Bool {
        if method == NSURLAuthenticationMethodNegotiate, failures == 0 {
            return false
        }
        return pageHosts.contains { $0?.lowercased() == host.lowercased() }
    }

    /// Identity of a protected area: one sheet at a time for it.
    static func key(of space: URLProtectionSpace) -> String {
        [space.protocol ?? "", space.host.lowercased(), String(space.port), space.realm ?? "", space.authenticationMethod]
            .joined(separator: "\u{1F}")
    }

    /// Methods for which the user types a user name and password; the others (certificates) are left to the system.
    static func asksForPassword(_ method: String) -> Bool {
        [
            NSURLAuthenticationMethodDefault,
            NSURLAuthenticationMethodHTTPBasic,
            NSURLAuthenticationMethodHTTPDigest,
            NSURLAuthenticationMethodNTLM,
            NSURLAuthenticationMethodNegotiate,
        ].contains(method)
    }
}

/// The answer of a login sheet; `credential` nil: cancelled.
nonisolated struct LoginAnswer: Sendable {
    var credential: URLCredential?
    /// The page may show no more dialogs or sheets until its next document.
    var suppressesFurther = false
}

/// JavaScript dialogs and login sheets of a page's document: how many it showed, and whether the user stopped them;
/// the login sheets on screen, by protected area (`LoginRequest.key`). The sheets on screen end without an answer when
/// the document changes or the page goes (review IU15): their task is cancelled, the presenter ends the sheet.
@MainActor
final class PageDialogState {
    private(set) var shown = 0
    private(set) var isSuppressed = false
    var pendingLogins: [String: Task<LoginAnswer?, Never>] = [:]
    /// Cancellation of each sheet on screen (dialogs, file choice).
    private var sheets: [UUID: () -> Void] = [:]

    /// Runs `show` (a sheet); nil if the document changes or the page goes first.
    func present<Answer: Sendable>(_ show: @escaping @MainActor () async -> Answer?) async -> Answer? {
        let task = Task { await show() }
        let id = UUID()
        sheets[id] = { task.cancel() }
        defer { sheets[id] = nil }
        return await task.value
    }

    /// True while a sheet is on screen (tests).
    var hasSheetOnScreen: Bool {
        !sheets.isEmpty
    }

    /// The document changed or the page goes: its sheets end, without an answer.
    func endSheets() {
        sheets.values.forEach { $0() }
        sheets = [:]
        pendingLogins.values.forEach { $0.cancel() }
    }

    func didShow() {
        shown += 1
    }

    func suppress() {
        isSuppressed = true
    }

    func documentDidChange() {
        shown = 0
        isSuppressed = false
        endSheets()
    }
}
