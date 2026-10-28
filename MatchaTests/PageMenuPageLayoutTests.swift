@testable import Matcha
import Testing

/// Page menu (right-click outside a link, an image or text), as in Chrome: `PageMenuPlan.pageLayout`.
struct PageMenuPageLayoutTests {
    private let reload = "WKMenuItemIdentifierReload"
    private let inspect = "WKMenuItemIdentifierInspectElement"

    @Test func `a page gets back, forward, save, print, translate and source around reload`() {
        #expect(PageMenuPlan.pageLayout(for: [reload], separators: []) == [
            .command(.goBack), .command(.goForward), .webKit(0),
            .separator, .command(.saveAs), .command(.print), .command(.translate),
            .separator, .command(.viewSource),
        ])
    }

    @Test func `inspect element stays last, WebKit history items are replaced`() {
        let identifiers: [String?] = ["WKMenuItemIdentifierGoBack", "WKMenuItemIdentifierGoForward", reload, nil, "Autre", nil, inspect]
        #expect(PageMenuPlan.pageLayout(for: identifiers, separators: [3, 5]) == [
            .command(.goBack), .command(.goForward), .webKit(2),
            .separator, .command(.saveAs), .command(.print), .command(.translate),
            .separator, .webKit(4),
            .separator, .command(.viewSource), .webKit(6),
        ])
    }

    @Test func `link, image and text menus are left alone`() {
        #expect(PageMenuPlan.pageLayout(for: ["WKMenuItemIdentifierOpenLink", "WKMenuItemIdentifierCopyLink"], separators: []) == nil)
        #expect(PageMenuPlan.pageLayout(for: ["WKMenuItemIdentifierCopy"], separators: []) == nil)
    }
}
