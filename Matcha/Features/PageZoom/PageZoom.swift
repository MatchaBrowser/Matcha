import Foundation

/// Zoom of a page with ⌘+, ⌘-, ⌘0 and the “Zoom” row of the site settings (task 5.4): `WKWebView.pageZoom`, like
/// the CSS `zoom` property on the whole page (text and layout follow, not just the image).
@MainActor
enum PageZoom {
    /// True if `change` would modify the zoom of `page` (menus disabled at the end of the list or already at 100%).
    static func canApply(_ change: ZoomLevels.Change, to page: BrowserTab) -> Bool {
        page.isLoaded && change.level(from: page.pageZoom) != nil
    }

    /// Applies `change` to `page`; with `siteZooms`, the zoom is remembered for its site and spreads to its other
    /// open pages. Returns the new zoom, or nil if nothing changes.
    @discardableResult
    static func apply(_ change: ZoomLevels.Change, to page: BrowserTab, siteZooms: SiteZoomStore?) -> Double? {
        guard page.isLoaded, let level = change.level(from: page.pageZoom) else {
            return nil
        }
        if let siteZooms {
            siteZooms.setZoom(level, for: page)
        } else {
            page.setPageZoom(level)
        }
        return level
    }
}
