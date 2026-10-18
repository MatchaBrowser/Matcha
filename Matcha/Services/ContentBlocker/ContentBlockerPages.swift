import Foundation
import WebKit

/// Pages suivies par le bloqueur (tâche 6.2), par contrôleur de contenu : chaque page a le sien
/// (`WebConfigurationFactory.pageConfiguration`), ce qui permet de poser ou de retirer les listes page par page. Pour
/// chacune : sa vue web (rechargée quand l'exception de son site change), sa session (`ContentBlockerScope`), le site de
/// son document principal et si les listes y sont posées. Références faibles : une page fermée sort d'elle-même.
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

    /// Pages suivies encore ouvertes.
    var count: Int {
        pages.values.count { $0.controller != nil }
    }

    /// Suit (ou met à jour) la page de `webView`, qui va afficher un document de `site` ; renvoie sa clé.
    mutating func track(_ webView: WKWebView, site: String?, scope: ContentBlockerScope?) -> ObjectIdentifier {
        let controller = webView.configuration.userContentController
        let key = ObjectIdentifier(controller)
        // Une clé peut resservir à un nouveau contrôleur à la même adresse : l'ancienne page est alors oubliée.
        var page = pages[key].flatMap { $0.controller === controller ? $0 : nil } ?? Page(controller: controller)
        page.webView = webView
        page.scope = scope
        page.site = site
        pages[key] = page
        return key
    }

    /// Pose ou retire `lists` sur chaque page (ou seulement celle de `key`) selon `blocks` ; renvoie les pages qui ont
    /// changé. Les pages fermées sont oubliées au passage.
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
