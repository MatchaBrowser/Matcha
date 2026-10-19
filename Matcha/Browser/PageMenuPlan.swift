import Foundation

/// Items of WebKit's context menu that Matcha replaces (task 5.9). Their identifiers (`NSMenuItem.identifier`) are
/// not documented: no public header of the macOS 27 SDK declares them. Values taken from a real WebKit menu
/// (`PageMenuIntegrationTests`); if WebKit changes them, its item stays as is.
nonisolated enum WebKitMenuItem: String, CaseIterable, Sendable {
    case openLinkInNewWindow = "WKMenuItemIdentifierOpenLinkInNewWindow"
    case openImageInNewWindow = "WKMenuItemIdentifierOpenImageInNewWindow"
}

/// Matcha item in the context menu of pages.
nonisolated enum PageMenuItem: String, Equatable, Sendable {
    /// “Open Link in New Tab”, in place of “… in New Window”.
    case openLinkInNewTab = "OpenLinkInNewTab"
    /// “Open Link in Peek”, right after.
    case openLinkInPeek = "OpenLinkInPeek"
    /// “Open Image in New Tab”, in place of “… in New Window”.
    case openImageInNewTab = "OpenImageInNewTab"

    /// Identifier of the menu item, modeled on WebKit's (without it, AppKit gives the name of the action).
    var identifier: String {
        "MatchaMenuItemIdentifier" + rawValue
    }

    /// What the window WebKit opens for this choice becomes.
    var destination: PageMenuDestination {
        switch self {
        case .openLinkInNewTab, .openImageInNewTab:
            .backgroundTab
        case .openLinkInPeek:
            .peek
        }
    }
}

/// Where the page that a context menu choice opens goes.
nonisolated enum PageMenuDestination: Equatable, Sendable {
    /// A background tab, after the originating tab (like ⌘-click).
    case backgroundTab
    /// Peek (task 4.4).
    case peek
}

/// A WebKit item (by its position in the original menu) and the Matcha items that replace it, in order. Each of
/// them triggers the replaced WebKit item.
nonisolated struct PageMenuReplacement: Equatable, Sendable {
    let index: Int
    let items: [PageMenuItem]
}

/// Rewriting of the context menu of pages, with no dependency on the UI: only the identifiers matter.
nonisolated enum PageMenuPlan {
    /// Replacements to make in a menu whose items have these identifiers (nil: no identifier), in menu order. An
    /// absent identifier: nothing changes for it. Only its first occurrence counts.
    /// `offersPeek`: “Open Link in Peek” makes sense here (tab of the sidebar, neither Peek nor another window).
    static func replacements(for identifiers: [String?], offersPeek: Bool) -> [PageMenuReplacement] {
        WebKitMenuItem.allCases.compactMap { original in
            identifiers.firstIndex(of: original.rawValue).map { index in
                PageMenuReplacement(index: index, items: items(replacing: original, offersPeek: offersPeek))
            }
        }
        .sorted { $0.index < $1.index }
    }

    private static func items(replacing original: WebKitMenuItem, offersPeek: Bool) -> [PageMenuItem] {
        switch original {
        case .openLinkInNewWindow:
            offersPeek ? [.openLinkInNewTab, .openLinkInPeek] : [.openLinkInNewTab]
        case .openImageInNewWindow:
            [.openImageInNewTab]
        }
    }
}
