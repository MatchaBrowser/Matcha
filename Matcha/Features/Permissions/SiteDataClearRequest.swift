import SwiftUI
import WebKit

/// Clearing a site's cookies and data, requested from the site settings panel (task 5.2): the tab and its site at
/// the time of the click.
struct SiteDataClearRequest {
    let tab: BrowserTab
    let origin: SiteOrigin

    /// Clears the site's data in the data store of the tab's profile (private window: its own) and its icon (review
    /// SV1), then reloads the page.
    func perform(favicons: FaviconService) async {
        let store = tab.webView?.configuration.websiteDataStore ?? tab.configuration.websiteDataStore
        await WebsiteDataCleaner.removeData(forHost: origin.host, in: store)
        await favicons.removeIcon(forHost: origin.host)
        tab.reload()
    }
}
