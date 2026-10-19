import AppKit
import OSLog
import WebKit

/// What an extension can do with a tab (task 6.3). Not supported (WebKit error “not implemented”): muting (no public
/// API), reader mode, multiple selection outside splits (`setSelected`), changing the parent tab.
extension ExtensionTab {
    typealias Completion = @Sendable ((any Error)?) -> Void

    /// A web page, or a page of the same extension: WebKit refuses to switch from one to the other in the same web view
    /// (`WKWebExtensionContext.webViewConfiguration`); these pages open in a new tab (`FEATURES.md`).
    func loadURL(_ url: URL, for context: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page, let owner else {
            completionHandler(ExtensionError.notFound)
            return
        }
        guard ExtensionURLPolicy.allows(url, from: context.baseURL) else {
            completionHandler(ExtensionError.forbiddenURL)
            return
        }
        guard ExtensionManager.isExtensionURL(url) == ExtensionManager.isExtensionURL(page.url) else {
            completionHandler(ExtensionError.unsupported("An extension page and a webpage cannot replace each other in a tab."))
            return
        }
        page.load(url)
        if case let .miniWindow(controller, _) = owner {
            controller.showWebView()
        }
        completionHandler(nil)
    }

    /// Reloads the page; a tab without a web view (unloaded, asleep) recreates it, which reloads it.
    func reload(fromOrigin: Bool, for _: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page else {
            completionHandler(ExtensionError.notFound)
            return
        }
        if let webView = page.webView, fromOrigin {
            webView.reloadFromOrigin()
        } else if page.webView != nil {
            page.reload()
        } else {
            page.makeWebViewIfNeeded()
        }
        completionHandler(nil)
    }

    func goBack(for _: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page, page.canGoBack else {
            completionHandler(ExtensionError.unsupported("The tab cannot go back."))
            return
        }
        page.goBack()
        completionHandler(nil)
    }

    func goForward(for _: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page, page.canGoForward else {
            completionHandler(ExtensionError.unsupported("The tab cannot go forward."))
            return
        }
        page.goForward()
        completionHandler(nil)
    }

    /// Like a click in the sidebar, without taking keyboard focus: the window displays the tab's Space, Peek closes and
    /// the tab is selected. Peek, and the page of a mini window or of a sign-in window, are always active.
    func activate(for _: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page, let owner else {
            completionHandler(ExtensionError.notFound)
            return
        }
        if case let .space(space, model) = owner {
            if model.space !== space {
                model.select(space)
            }
            space.tabManager.closePeek()
            space.tabManager.select(page)
        }
        windows?.update()
        completionHandler(nil)
    }

    /// Like ⌘W: a Today tab closes; a pinned tab or a favorite goes back to its original address and unloads, but stays
    /// in the sidebar (as in Arc); Peek closes; the page of a mini window or of a sign-in window closes that window.
    func close(for _: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page, let owner else {
            completionHandler(ExtensionError.notFound)
            return
        }
        switch owner {
        case let .space(space, _):
            space.tabManager.close(page)
        case let .peek(space, _):
            PeekActions.close(in: space.tabManager)
        case let .miniWindow(controller, _):
            controller.close()
        case let .popupWindow(controller, _):
            controller.close()
        }
        windows?.update()
        completionHandler(nil)
    }

    /// Pinning moves the Today tab to the end of the pinned tabs; unpinning (a pinned tab or a favorite) puts it back
    /// at the top of the Today tabs, like the sidebar menu.
    func setPinned(_ pinned: Bool, for context: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page, case let .space(space, _) = owner else {
            completionHandler(ExtensionError.unsupported("Only tabs of a browser window can be pinned."))
            return
        }
        if pinned != isPinned(for: context) {
            space.tabManager.setPlace(page, to: pinned ? .pinned : .today)
        }
        windows?.update()
        completionHandler(nil)
    }

    /// Zoom of the page's website, like ⌘+ and ⌘- (task 5.4): all open pages of this website take it, like Chrome's
    /// “per-origin” scope.
    func setZoomFactor(_ zoomFactor: Double, for _: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page else {
            completionHandler(ExtensionError.notFound)
            return
        }
        if let siteZooms = owner?.siteZooms {
            siteZooms.setZoom(zoomFactor, for: page)
        } else {
            page.setPageZoom(ZoomLevels.clamped(zoomFactor))
        }
        completionHandler(nil)
    }

    /// Like “Duplicate Tab” in the sidebar: the copy, with its history, opens right after the tab; it is active only if
    /// the extension asks for it.
    func duplicate(
        using configuration: WKWebExtension.TabConfiguration,
        for _: WKWebExtensionContext,
        completionHandler: @escaping @Sendable ((any WKWebExtensionTab)?, (any Error)?) -> Void,
    ) {
        guard let page, case let .space(space, _) = owner else {
            completionHandler(nil, ExtensionError.unsupported("Only tabs of a browser window can be duplicated."))
            return
        }
        let copy = space.tabManager.duplicate(page)
        if !configuration.shouldBeActive {
            space.tabManager.select(page)
        }
        windows?.update()
        completionHandler(windows?.adapter(for: copy), nil)
    }
}
