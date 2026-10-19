import AppKit
import OSLog
import SwiftUI
import WebKit

/// A mini window: its panel, its page (a `BrowserTab` outside any Space, never saved), the container of its web
/// view and its command bar. Created and tracked by `MiniWindowManager`.
@MainActor
final class MiniWindowController: NSObject, Identifiable {
    let id = UUID()
    let tab: BrowserTab
    /// Profile whose cookies the page uses (that of the Space displayed at opening).
    let profileID: UUID?
    let commandBar: MiniCommandBarModel
    let panel: MiniWindowPanel
    let container = MiniWebViewContainer()
    /// “URL Copied” confirmation of this mini window (⇧⌘C, “Copy URL” row).
    let copyConfirmation = CopyConfirmationModel()
    private weak var manager: MiniWindowManager?
    /// The page has gone into a Space: closing must not release it.
    private(set) var isHandedOff = false

    init(tab: BrowserTab, profileID: UUID?, frame: CGRect, manager: MiniWindowManager) {
        self.tab = tab
        self.profileID = profileID
        self.manager = manager
        commandBar = MiniCommandBarModel(
            tab: tab,
            faviconService: manager.session.faviconService,
            history: manager.session.history.map { ProfileHistory(store: $0, profileID: profileID) },
        )
        panel = MiniWindowPanel(frame: frame)
        super.init()
        panel.delegate = self
        // ⎋ that nobody kept: a mini window without a page closes; with a page, nothing (the page stays).
        panel.cancelHandler = { [weak self] in
            if let self, tab.url == nil {
                close()
            }
        }
        let host = NSHostingView(rootView: MiniWindowView(controller: self, manager: manager))
        // The size comes from the panel (set by the user), never from the SwiftUI content.
        host.sizingOptions = []
        panel.contentView = host
        showWebView()
    }

    /// Shows the page's web view (created on the first load).
    func showWebView() {
        if let webView = tab.webView {
            container.attach(webView)
        }
    }

    // MARK: Command bar

    /// ⌘L and click on the address; ⌘T, ⌥⌘N and the menu: fresh input.
    func showCommandBar(_ mode: MiniCommandBarMode) {
        commandBar.present(mode, settings: manager?.commandBarSettings() ?? MiniWindowSettings.current())
    }

    /// ⏎ or click on a row: the bar closes, then the page loads the address (or it is copied) and takes the
    /// keyboard.
    func submit(_ rowID: CommandRow.ID?) {
        let submission = commandBar.submission(for: rowID)
        guard submission != .ignore else {
            return
        }
        commandBar.dismiss()
        panel.makeFirstResponder(nil)
        switch submission {
        case let .load(url):
            Logger.miniWindow.info("Adresse chargée dans une mini-fenêtre")
            tab.load(url)
            showWebView()
        case .copyURL:
            copyURL()
        case .ignore:
            return
        }
        TabActivation.focusPage(of: tab)
    }

    /// ⎋ in the field: the bar closes; without a page, the mini window too (nothing remains).
    func cancelCommandBar() {
        commandBar.dismiss()
        guard tab.url != nil else {
            close()
            return
        }
        panel.makeFirstResponder(nil)
        TabActivation.focusPage(of: tab)
    }

    /// ⌘W: closes the bar if it is open, otherwise the mini window.
    func closeCommand() {
        if commandBar.isPresented {
            cancelCommandBar()
        } else {
            close()
        }
    }

    /// ⇧⌘C and the “Copy URL” row: the page's address, with the “URL Copied” confirmation.
    func copyURL(to pasteboard: NSPasteboard = .general) {
        guard let url = tab.url else {
            return
        }
        TabLinkCopier.copy(url, to: pasteboard)
        copyConfirmation.show()
        // Never the address itself.
        Logger.miniWindow.info("Adresse copiée depuis une mini-fenêtre")
    }

    // MARK: Closing

    /// “Open in Space”: the web view leaves the container right away, before the main window displays it; the
    /// closing that follows does not release the page.
    func detachForHandOff() {
        isHandedOff = true
        commandBar.dismiss()
        container.detach()
    }

    /// Every closing goes through here (×, ⌘W, ⇧⌘W, ⎋ without a page, `window.close()`, hand-off, deleted profile).
    func close() {
        panel.close()
    }
}

extension MiniWindowController: NSWindowDelegate {
    func windowDidBecomeKey(_: Notification) {
        manager?.keyChanged(self, isKey: true)
    }

    func windowDidResignKey(_: Notification) {
        manager?.keyChanged(self, isKey: false)
    }

    func windowDidEndLiveResize(_: Notification) {
        manager?.rememberSize(panel.frame.size)
    }

    /// Closing for good: the page is released (sound, process), unless it has gone into a Space.
    func windowWillClose(_: Notification) {
        commandBar.dismiss()
        copyConfirmation.cancel()
        if !isHandedOff {
            container.detach()
            tab.unload(resettingTo: nil, title: nil)
        }
        manager?.didClose(self)
        panel.delegate = nil
        panel.cancelHandler = nil
        // Keeps the controller alive until the end of the closing, then releases the SwiftUI view (which retains it).
        Task { @MainActor in
            self.panel.contentView = nil
        }
    }
}
