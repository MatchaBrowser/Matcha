import Foundation
import WebKit

/// Pages tracked by the blocker (task 6.2), by content controller: each page has its own
/// (`WebConfigurationFactory.pageConfiguration`), which lets lists be added or removed page by page. For each one:
/// its web view (reloaded when its website's exception changes), its session (`ContentBlockerScope`), the website of
/// its main document, and whether the lists are added to it. Weak references: a closed page drops out on its own.
@MainActor
struct ContentBlockerPages {
    struct Page {
        fileprivate(set) weak var controller: WKUserContentController?
        fileprivate(set) weak var webView: WKWebView?
        fileprivate(set) weak var scope: ContentBlockerScope?
        fileprivate(set) var site: String?
        fileprivate(set) var hasLists = false
    }

    private var pages: [ObjectIdentifier: Page] = [:]

    /// Tracked pages that are still open.
    var count: Int {
        pages.values.count { $0.controller != nil }
    }

    /// Tracks (or updates) the page of `webView`, which is about to show a document from `site`; returns its key.
    mutating func track(_ webView: WKWebView, site: String?, scope: ContentBlockerScope?) -> ObjectIdentifier {
        let controller = webView.configuration.userContentController
        let key = ObjectIdentifier(controller)
        // A key can be reused by a new controller at the same address: the old page is then forgotten.
        var page = pages[key].flatMap { $0.controller === controller ? $0 : nil } ?? Page(controller: controller)
        page.webView = webView
        page.scope = scope
        page.site = site
        pages[key] = page
        return key
    }

    /// Adds or removes `lists` on each page (or only the one for `key`) according to `blocks`; returns the pages that
    /// changed. Closed pages are forgotten along the way.
    @discardableResult
    mutating func apply(_ lists: [WKContentRuleList], only key: ObjectIdentifier? = nil, blocks: (Page) -> Bool) -> [Page] {
        pages = pages.filter { $0.value.controller != nil }
        var changed: [Page] = []
        for (pageKey, var page) in pages where key == nil || key == pageKey {
            guard let controller = page.controller else {
                continue
            }
            let shouldBlock = blocks(page)
            guard shouldBlock != page.hasLists else {
                continue
            }
            if shouldBlock {
                lists.forEach(controller.add)
            } else {
                lists.forEach(controller.remove)
            }
            page.hasLists = shouldBlock
            pages[pageKey] = page
            changed.append(page)
        }
        return changed
    }
}
