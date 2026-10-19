import AppKit
import WebKit

/// A tab as extensions see it (task 6.3): `WKWebExtensionTab` adapter of a `BrowserTab`, designated by its identifier
/// and looked up again in `ExtensionWindows` at each question (a favorite can change object when a Space takes back its
/// copy). One object per tab, always the same while it is open: WebKit recognizes tabs by their object. `BrowserTab` is
/// not an `NSObject`: it does not adopt the protocol itself. Actions: `+Actions`.
@MainActor
final class ExtensionTab: NSObject, WKWebExtensionTab {
    let tabID: UUID
    /// Window the tab is in, or was in just before it closed (`tabs.onRemoved` event).
    var windowID: UUID?
    private(set) weak var windows: ExtensionWindows?

    init(id: UUID, windows: ExtensionWindows) {
        tabID = id
        self.windows = windows
    }

    /// The live tab; nil once closed.
    var page: BrowserTab? {
        windows?.liveTab(tabID)?.tab
    }

    var owner: ExtensionTabOwner? {
        windows?.liveTab(tabID)?.owner
    }

    func window(for _: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        guard let windowID, let windows else {
            return nil
        }
        return windows.windowAdapter(windowID)
    }

    func indexInWindow(for _: WKWebExtensionContext) -> Int {
        windows?.location(ofTab: tabID)?.index ?? NSNotFound
    }

    /// Tab from which this one was opened (link, `window.open`), if it is still open.
    func parentTab(for _: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let windows, let openerID = page?.openerID, windows.location(ofTab: openerID) != nil else {
            return nil
        }
        return windows.tabAdapter(openerID)
    }

    /// Web view of the page, if it is loaded and plugged into this extension's controller (otherwise WebKit rejects
    /// it).
    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        guard let webView = page?.webView, let controller = context.webExtensionController,
              webView.configuration.webExtensionController === controller
        else {
            return nil
        }
        return webView
    }

    func title(for _: WKWebExtensionContext) -> String? {
        page?.title
    }

    /// Favorites and pinned tabs: always at the top of their Space, like Chrome's pinned tabs.
    func isPinned(for _: WKWebExtensionContext) -> Bool {
        windows?.state.tabs[tabID]?.isPinned ?? false
    }

    func isPlayingAudio(for _: WKWebExtensionContext) -> Bool {
        page?.isPlayingAudio ?? false
    }

    func zoomFactor(for _: WKWebExtensionContext) -> Double {
        page?.pageZoom ?? 1
    }

    /// Address of the tab, even when unloaded or asleep (without a web view).
    func url(for _: WKWebExtensionContext) -> URL? {
        page?.url
    }

    /// A tab without a web view (unloaded, asleep) is “complete”.
    func isLoadingComplete(for _: WKWebExtensionContext) -> Bool {
        !(page?.isLoading ?? false)
    }

    /// Panes of the split displayed by its window (the active tab included).
    func isSelected(for _: WKWebExtensionContext) -> Bool {
        windows?.isSelected(tabID) ?? false
    }
}
