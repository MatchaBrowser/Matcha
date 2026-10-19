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
    /// User name and password typed for a website that asks for them; nil: cancelled.
    func credential(for login: LoginRequest, for webView: WKWebView) async -> URLCredential?
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

    func credential(for _: LoginRequest, for _: WKWebView) async -> URLCredential? {
        nil
    }

    func save(_: BrowserTab) {}

    func print(_: BrowserTab) {}
}

/// A JavaScript dialog, as shown: never longer than `maximumLength`, with the website of the frame that opens it.
nonisolated struct PageDialog: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case alert
        case confirm
        case prompt(defaultText: String)
    }

    static let maximumLength = 2000

    let kind: Kind
    let message: String
    /// Website of the frame that opens it; nil for a page without one (local file).
    let site: String?
    /// “Don't allow this page to show more dialogs”, from the second dialog of a page on.
    let offersSuppression: Bool

    init(kind: Kind, message: String, site: String?, offersSuppression: Bool) {
        self.kind = kind
        self.message = message.count > Self.maximumLength ? String(message.prefix(Self.maximumLength)) + "…" : message
        self.site = site
        self.offersSuppression = offersSuppression
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

/// JavaScript dialogs of a page's document: how many it showed, and whether the user stopped them.
@MainActor
final class PageDialogState {
    private(set) var shown = 0
    private(set) var isSuppressed = false

    func didShow() {
        shown += 1
    }

    func suppress() {
        isSuppressed = true
    }

    func documentDidChange() {
        shown = 0
        isSuppressed = false
    }
}
