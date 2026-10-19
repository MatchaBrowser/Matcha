import AppKit
import SwiftUI
import WebKit

/// A sign-in window (task 5.8): its window, its page (a `BrowserTab` outside any Space, never saved), the
/// container of its web view and the page that opened it. Created and tracked by `PopupWindowManager`.
///
/// It is a child window of the originating window: it stays above it (a click on the browser window does not hide
/// it), follows it when it is moved and takes its level (above the other windows with a mini window). AppKit
/// removes children from the screen with their parent: when the originating window closes, the sign-in window
/// detaches from it and stays open.
@MainActor
final class PopupWindowController: NSObject, Identifiable {
    let id = UUID()
    let tab: BrowserTab
    let opener: PopupOpener
    let window: PopupWindow
    let container = MiniWebViewContainer()
    private weak var manager: PopupWindowManager?
    private var parentObserver: (any NSObjectProtocol)?

    init(tab: BrowserTab, opener: PopupOpener, frame: CGRect, isPrivate: Bool, manager: PopupWindowManager) {
        self.tab = tab
        self.opener = opener
        self.manager = manager
        window = PopupWindow(frame: frame)
        super.init()
        window.delegate = self
        // Private window: dark, like it.
        if isPrivate {
            window.appearance = NSAppearance(named: .darkAqua)
        }
        let host = NSHostingView(rootView: PopupWindowView(controller: self))
        // The size comes from the window (requested by the page, then set by the user), never from the content.
        host.sizingOptions = []
        window.contentView = host
        if let webView = tab.webView {
            container.attach(webView)
        }
    }

    /// Places the window above `parent`, the originating window, as long as the latter is open.
    func attach(to parent: NSWindow) {
        detachFromParent()
        parent.addChildWindow(window, ordered: .above)
        // No queue: called during closing, before AppKit removes the child windows from the screen.
        parentObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: parent,
            queue: nil,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.detachFromParent() }
        }
    }

    /// No more parent window: the window stays where it is, at the normal level (otherwise a child keeps the level
    /// of its former parent, verified).
    func detachFromParent() {
        if let parentObserver {
            NotificationCenter.default.removeObserver(parentObserver)
            self.parentObserver = nil
        }
        if let parent = window.parent {
            parent.removeChildWindow(window)
            window.level = .normal
        }
    }

    /// Closing by the app: the page's `window.close()`, private window or profile closed, window that only
    /// downloads. The button, ⌘W and ⇧⌘W close the window directly; everything ends in `windowWillClose`.
    func close() {
        window.close()
    }
}

extension PopupWindowController: NSWindowDelegate {
    /// Closing for good: the page is released (sound, process, permission requests denied).
    func windowWillClose(_: Notification) {
        detachFromParent()
        container.detach()
        tab.unload(resettingTo: nil, title: nil)
        manager?.didClose(self)
        window.delegate = nil
        // Keeps the controller alive until the end of closing, then releases the SwiftUI view (which retains it).
        Task { @MainActor in
            self.window.contentView = nil
        }
    }
}
