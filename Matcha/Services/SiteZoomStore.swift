import Foundation
import Observation
import OSLog

/// Page zoom remembered per website (task 5.4), for all profiles: a reading setting, like text size, not website data.
/// Each new document of a page (tab, Peek, mini window) takes the zoom of its website (`pageDidCommit`); a change
/// applies immediately to all open pages of that website, as in Safari. 100% is not remembered. Saved in the app's
/// settings (`siteZoomLevels`); without `defaults` (private window, test store), everything stays in memory and goes
/// away with the session.
@MainActor
@Observable
final class SiteZoomStore {
    /// App setting: website → zoom (1.25 for 125%).
    static let defaultsKey = "siteZoomLevels"

    /// Zoom of each website that is not at 100%.
    private(set) var levels: [String: Double]
    @ObservationIgnored private let defaults: UserDefaults?
    /// Open pages and the website of their displayed document, to apply a change of that website's zoom to them.
    @ObservationIgnored private var pages: [ObjectIdentifier: OpenPage] = [:]

    private struct OpenPage {
        weak var tab: BrowserTab?
        let site: String
    }

    /// `defaults`: where to remember the zooms; nil for a private window or a test store (nothing is written).
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        levels = Self.load(from: defaults)
    }

    /// True if the zooms are saved (false for a private window).
    var isPersistent: Bool {
        defaults != nil
    }

    /// Zoom remembered for `site`; 100% without a website or without a setting.
    func level(forSite site: String?) -> Double {
        site.flatMap { levels[$0] } ?? ZoomLevels.actualSize
    }

    /// New document in `tab` (`didCommit`, reload and going back included): the page takes the zoom of its website, or
    /// 100% without a website, and will from now on follow the changes of that website's zoom.
    func pageDidCommit(_ tab: BrowserTab, url: URL?) {
        let site = SiteZoomKey.key(for: url)
        track(tab, site: site)
        tab.setPageZoom(level(forSite: site))
    }

    /// ⌘+, ⌘-, ⌘0 on `tab`: the website of its document remembers `level`, and each of its open pages takes it. A page
    /// without a website changes alone, and nothing is remembered.
    func setZoom(_ level: Double, for tab: BrowserTab) {
        guard let site = site(of: tab) ?? SiteZoomKey.key(for: tab.url) else {
            tab.setPageZoom(ZoomLevels.clamped(level))
            return
        }
        track(tab, site: site)
        setLevel(level, forSite: site)
    }

    /// Site settings: `site` remembers `level` (100% forgets it), and all its open pages take it.
    func setLevel(_ level: Double, forSite site: String) {
        let level = ZoomLevels.clamped(level)
        levels[site] = ZoomLevels.isActualSize(level) ? nil : level
        save()
        for page in pages.values where page.site == site {
            page.tab?.setPageZoom(level)
        }
        Logger.browser.info("Site zoom: \(Int((level * 100).rounded()), privacy: .public) %, \(site, privacy: .private)")
    }

    /// Website of the document displayed by `tab`, if it is tracked.
    private func site(of tab: BrowserTab) -> String? {
        guard let page = pages[ObjectIdentifier(tab)], page.tab === tab else {
            return nil
        }
        return page.site
    }

    /// Tracks `tab` under `site` (nil: stops tracking it); released pages are forgotten along the way.
    private func track(_ tab: BrowserTab, site: String?) {
        pages = pages.filter { $0.value.tab != nil }
        pages[ObjectIdentifier(tab)] = site.map { OpenPage(tab: tab, site: $0) }
    }

    private func save() {
        guard let defaults else {
            return
        }
        if levels.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(levels, forKey: Self.defaultsKey)
        }
    }

    /// Saved zooms, clamped between 50% and 300%; an unreadable value or one at 100% is ignored.
    private static func load(from defaults: UserDefaults?) -> [String: Double] {
        let stored = defaults?.dictionary(forKey: defaultsKey) ?? [:]
        var levels: [String: Double] = [:]
        for (site, value) in stored {
            guard !site.isEmpty, let level = (value as? NSNumber)?.doubleValue, level.isFinite else {
                Logger.browser.notice("Unreadable saved zoom, ignored")
                continue
            }
            let clamped = ZoomLevels.clamped(level)
            if !ZoomLevels.isActualSize(clamped) {
                levels[site] = clamped
            }
        }
        return levels
    }
}
