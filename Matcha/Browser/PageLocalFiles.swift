import Foundation
import Observation
import WebKit

/// A local page that may read only itself (received from another app, review WB11) but refers to other local files,
/// next to it (images, style sheets, scripts): they don't show. The page's banner then proposes to open it with ⌘O,
/// which lets it read its folder. Read once the page has loaded, in a script world of its own.
@MainActor
@Observable
final class PageLocalFiles {
    /// The page refers to local files it can't read; false again at the next document, or once the banner is closed.
    private(set) var hasUnreadableNeighbors = false
    /// Only the answer about the current document counts.
    @ObservationIgnored private var generation = 0
    /// Answers of the pages read, for the tests: “no banner” is known once the page has answered.
    @ObservationIgnored private(set) var answers = 0

    static let world = WKContentWorld.world(name: "MatchaLocalFiles")

    /// True if the document loads (or tries to) another local file than itself; links don't count, they load nothing.
    static let script = """
    const page = location.href.split('#')[0];
    const selector = 'img[src], script[src], link[rel~="stylesheet"][href], link[rel~="icon"][href], '
        + 'source[src], video[src], audio[src], iframe[src], embed[src], object[data], input[type="image"][src]';
    for (const element of document.querySelectorAll(selector)) {
        const address = element.src || element.href || element.data || '';
        if (typeof address === 'string' && address.startsWith('file:') && address.split('#')[0] !== page) {
            return true;
        }
    }
    return false;
    """

    func documentDidChange() {
        generation += 1
        hasUnreadableNeighbors = false
    }

    /// The banner is closed: not shown again for this document.
    func dismiss() {
        generation += 1
        hasUnreadableNeighbors = false
    }

    /// The page of `webView` has loaded; `access`: what it may read (`BrowserTab.fileReadAccess`).
    func pageDidFinishLoading(in webView: WKWebView, access: URL?) {
        generation += 1
        hasUnreadableNeighbors = false
        guard let url = webView.url, url.isFileURL, let access, FileReadAccess.isLimitedToItself(access, file: url) else {
            return
        }
        let generation = generation
        webView.callAsyncJavaScript(Self.script, arguments: [:], in: nil, in: Self.world) { [weak self] result in
            guard let self, self.generation == generation else {
                return
            }
            answers += 1
            hasUnreadableNeighbors = (try? result.get()) as? Bool == true
        }
    }
}
