import AppKit
import WebKit

/// The system's dialogs and panels for a page (audits K1 to K3; “Save As…”, “Print…”), as sheets on its window:
/// AppKit queues them if one is already open. The website asking is the title, never the page's text. A page in no
/// visible window (tab in the background) gets “Cancel”.
@MainActor
final class SystemPageDialogs: PageDialogPresenting {
    func present(_ dialog: PageDialog, for webView: WKWebView) async -> PageDialogAnswer? {
        guard let window = webView.window, window.isVisible else {
            return nil
        }
        let alert = NSAlert()
        alert.messageText = Self.title(of: dialog)
        alert.informativeText = dialog.message
        alert.addButton(withTitle: String(localized: "OK"))
        if dialog.kind != .alert {
            alert.addButton(withTitle: String(localized: "Cancel"))
        }
        var field: NSTextField?
        if case let .prompt(defaultText) = dialog.kind {
            let textField = NSTextField(string: defaultText)
            textField.frame = NSRect(x: 0, y: 0, width: 300, height: 24)
            alert.accessoryView = textField
            alert.window.initialFirstResponder = textField
            field = textField
        }
        alert.showsSuppressionButton = dialog.offersSuppression
        alert.suppressionButton?.title = Self.suppressionTitle
        let response = await alert.beginSheetModal(for: window)
        return PageDialogAnswer(
            isConfirmed: response == .alertFirstButtonReturn,
            text: field?.stringValue,
            suppressesFurther: alert.suppressionButton?.state == .on,
        )
    }

    /// The website asking; without one, a frame inside the page never passes for the page (review WB7).
    private static func title(of dialog: PageDialog) -> String {
        if let site = dialog.site {
            return String(localized: "\(site) says", comment: "Title of a website's JavaScript dialog; %@ is the website")
        }
        if dialog.isFromEmbeddedFrame {
            return String(
                localized: "An embedded page says",
                comment: "Title of a JavaScript dialog of a frame without a website (data: address, sandboxed frame)",
            )
        }
        return String(localized: "This page says", comment: "Title of a JavaScript dialog of a page without a website (local file)")
    }

    func chooseFiles(allowsMultipleSelection: Bool, allowsDirectories: Bool, for webView: WKWebView) async -> [URL]? {
        guard let window = webView.window, window.isVisible else {
            return nil
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = allowsDirectories
        panel.allowsMultipleSelection = allowsMultipleSelection
        panel.prompt = String(localized: "Choose", comment: "Button of the panel where the user picks files to send to a website")
        guard await panel.beginSheetModal(for: window) == .OK else {
            return nil
        }
        return panel.urls
    }

    func credential(for login: LoginRequest, for webView: WKWebView) async -> LoginAnswer? {
        guard let window = webView.window, window.isVisible else {
            return nil
        }
        let alert = NSAlert()
        alert.messageText = String(
            localized: "Log in to \(login.site)",
            comment: "Title of the sheet where a website asks for a user name and password; %@ is the website",
        )
        alert.informativeText = Self.explanation(of: login)
        alert.addButton(withTitle: String(
            localized: "Log In",
            comment: "Button of the sheet where a website asks for a user name and password",
        ))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let user = NSTextField(string: login.user ?? "")
        user.placeholderString = String(
            localized: "User Name",
            comment: "Field of the sheet where a website asks for a user name and password",
        )
        let password = NSSecureTextField(string: "")
        password.placeholderString = String(
            localized: "Password",
            comment: "Field of the sheet where a website asks for a user name and password",
        )
        // Fixed frames: the alert sizes its accessory view from its frame (a stack view would shrink the fields).
        let fields = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 56))
        user.frame = NSRect(x: 0, y: 32, width: 240, height: 24)
        password.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        fields.addSubview(user)
        fields.addSubview(password)
        alert.accessoryView = fields
        alert.window.initialFirstResponder = login.user == nil ? user : password
        alert.showsSuppressionButton = login.offersSuppression
        alert.suppressionButton?.title = Self.suppressionTitle
        let isConfirmed = await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
        return LoginAnswer(
            credential: isConfirmed ? URLCredential(user: user.stringValue, password: password.stringValue, persistence: .forSession) : nil,
            suppressesFurther: alert.suppressionButton?.state == .on,
        )
    }

    /// Checkbox of a page's dialogs and login sheets, from the second one on (audit K1, review WB6).
    private static var suppressionTitle: String {
        String(
            localized: "Don't allow this page to show more dialogs",
            comment: "Checkbox of a website's JavaScript dialog, from its second dialog on",
        )
    }

    /// The area the server names (its words, quoted), a refused attempt, and a warning if the password travels
    /// unencrypted.
    private static func explanation(of login: LoginRequest) -> String {
        var lines: [String] = []
        if let realm = login.realm, !realm.isEmpty {
            lines.append(String(
                localized: "The website says: “\(realm)”",
                comment: "Login sheet: the name the server gives to its protected area; %@ is that name",
            ))
        }
        if login.failedBefore {
            lines.append(String(localized: "The user name or password isn't correct.", comment: "Login sheet, after a refused attempt"))
        }
        if !login.isSecure {
            lines.append(String(
                localized: "Your password will be sent unencrypted.",
                comment: "Login sheet of a website without encryption",
            ))
        }
        return lines.joined(separator: "\n\n")
    }

    func save(_ page: BrowserTab) {
        PageSaver.start(for: page)
    }

    func print(_ page: BrowserTab) {
        PagePrinter.print(page)
    }
}
