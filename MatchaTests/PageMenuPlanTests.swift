@testable import Matcha
import Testing

/// Rewrite of the page context menu (task 5.9), on the WebKit item identifiers captured on macOS 27
/// (`PageMenuIntegrationTests` checks them on a real menu).
struct PageMenuPlanTests {
    /// Link menu, in WebKit's order.
    static let linkMenu: [String?] = [
        "WKMenuItemIdentifierOpenLink",
        "WKMenuItemIdentifierOpenLinkInNewWindow",
        "WKMenuItemIdentifierDownloadLinkedFile",
        "WKMenuItemIdentifierCopyLink",
        nil,
        "WKMenuItemIdentifierShareMenu",
    ]

    /// Image menu.
    static let imageMenu: [String?] = [
        "WKMenuItemIdentifierOpenImageInNewWindow",
        "WKMenuItemIdentifierDownloadImage",
        "WKMenuItemIdentifierCopyImage",
        "WKMenuItemIdentifierCopySubject",
        "WKMenuItemIdentifierRevealImage",
        nil,
    ]

    @Test func `a link gets a new tab and Peek in place of the new window`() {
        let replacements = PageMenuPlan.replacements(for: Self.linkMenu, offersPeek: true)
        #expect(replacements == [PageMenuReplacement(index: 1, items: [.openLinkInNewTab, .openLinkInPeek])])
    }

    @Test func `without Peek a link only gets a new tab`() {
        let replacements = PageMenuPlan.replacements(for: Self.linkMenu, offersPeek: false)
        #expect(replacements == [PageMenuReplacement(index: 1, items: [.openLinkInNewTab])])
    }

    @Test func `an image gets a new tab in place of the new window`() {
        #expect(PageMenuPlan.replacements(for: Self.imageMenu, offersPeek: true) == [PageMenuReplacement(
            index: 0,
            items: [.openImageInNewTab],
        )])
    }

    /// Image inside a link: the link menu, then the image menu; replacements in menu order.
    @Test func `a linked image gets both replacements in menu order`() {
        let menu = Array(Self.linkMenu.prefix(5)) + Self.imageMenu + [Self.linkMenu[5]]
        let replacements = PageMenuPlan.replacements(for: menu, offersPeek: true)
        #expect(replacements == [
            PageMenuReplacement(index: 1, items: [.openLinkInNewTab, .openLinkInPeek]),
            PageMenuReplacement(index: 5, items: [.openImageInNewTab]),
        ])
    }

    @Test(arguments: [
        [String?](),
        ["WKMenuItemIdentifierReload", nil],
        [nil, nil, nil],
        ["WKMenuItemIdentifierOpenLink", "WKMenuItemIdentifierOpenLinkInNewTab", "WKMenuItemIdentifierCopyLink"],
        ["openLinkInNewWindow", "wkmenuitemidentifieropenlinkinnewwindow"],
    ])
    func `a menu without the expected identifiers is left unchanged`(identifiers: [String?]) {
        #expect(PageMenuPlan.replacements(for: identifiers, offersPeek: true).isEmpty)
    }

    @Test func `only the first occurrence of an identifier is replaced`() {
        let menu: [String?] = ["WKMenuItemIdentifierOpenLinkInNewWindow", "WKMenuItemIdentifierOpenLinkInNewWindow"]
        #expect(PageMenuPlan.replacements(for: menu, offersPeek: false) == [PageMenuReplacement(index: 0, items: [.openLinkInNewTab])])
    }

    @Test func `new tab items open a background tab and Peek opens Peek`() {
        #expect(PageMenuItem.openLinkInNewTab.destination == .backgroundTab)
        #expect(PageMenuItem.openImageInNewTab.destination == .backgroundTab)
        #expect(PageMenuItem.openLinkInPeek.destination == .peek)
    }
}
