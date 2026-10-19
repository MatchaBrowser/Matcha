import Foundation
import Observation
import WebKit

/// The blocker as seen from a session (task 6.2): its pages tell it which document they are about to load, and its
/// site settings read or change a website's exception. The main session reads and writes the saved exceptions; a
/// private window (or a test store) reads them, but its changes stay in memory and go away with it: nothing visited
/// there is written.
@MainActor
@Observable
final class ContentBlockerScope {
    @ObservationIgnored let service: ContentBlockerService
    /// False: exception changes stay in this session (`overrides`).
    @ObservationIgnored let savesExceptions: Bool
    /// Exceptions changed in this session without being saved: website → exception (true) or blocking (false).
    private var overrides: [String: Bool] = [:]

    init(service: ContentBlockerService, savesExceptions: Bool) {
        self.service = service
        self.savesExceptions = savesExceptions
    }

    /// True if the blocker is turned off on `site` for the pages of this session.
    func isExcepted(site: String) -> Bool {
        overrides[site] ?? service.exceptions.contains(site)
    }

    /// Blocks (or not) on `site`; the open pages of that website in the affected sessions reload.
    func setBlocks(_ blocks: Bool, onSite site: String) {
        guard let site = ContentBlockerExceptions.normalized(site), isExcepted(site: site) == blocks else {
            return
        }
        if savesExceptions {
            service.setException(!blocks, forSite: site)
        } else {
            overrides[site] = !blocks
            service.exceptionsDidChange(forSite: site)
        }
    }

    /// The main document of `webView` is about to be `url` (navigation allowed, before it loads; or document shown):
    /// the lists are added to it or removed from it according to its website.
    func prepare(_ webView: WKWebView, for url: URL?) {
        service.prepare(webView, for: url, scope: self)
    }
}
