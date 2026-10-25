import Foundation
import SwiftData

/// The icons kept on disk follow the history (review SV1): once visits are erased, only the icons of the websites
/// still in the history or in a tab (favorites, pinned and Today tabs of every profile) stay.
extension BrowserSession {
    /// Erases the icons of the websites that neither the history nor a tab has anymore.
    func forgetUnusedIcons() async {
        guard let history else {
            return
        }
        var hosts = await history.visitedHosts()
        hosts.formUnion(tabHosts())
        await faviconService.removeIcons(keeping: hosts)
    }

    /// Domains of the saved tabs, and of the open ones (their address may not be saved yet).
    private func tabHosts() -> Set<String> {
        let records = (try? container.mainContext.fetch(FetchDescriptor<TabRecord>())) ?? []
        let open = (spaces.map(\.tabManager) + windowTabs.map(\.tabManager)).flatMap(\.tabs)
        let urls = records.flatMap { [$0.url, $0.pinnedURL] } + open.flatMap { [$0.url, $0.pinnedURL] }
        return Set(urls.compactMap { $0?.host() })
    }
}
