import SwiftUI

/// How the browser window shows its sidebar (review TS12: the view's rules, tested apart): fixed, floating over the
/// page (hidden sidebar hovered), or reduced to a column of icons; the window's buttons, and the margins of the card.
nonisolated struct SidebarPresentation: Equatable {
    var isSidebarVisible: Bool
    /// The hidden sidebar is shown over the page (hovered, or held by one of its presentations).
    var isFloatingSidebarShown: Bool
    var hiddenSidebarStyle: HiddenSidebarStyle

    /// Hidden sidebar reduced to a column of icons (setting), under a bar with the window's buttons.
    var showsCompactSidebar: Bool {
        !isSidebarVisible && hiddenSidebarStyle == .icons
    }

    /// As in Arc, the window's buttons disappear with the sidebar; the column of icons keeps them, in its bar.
    var showsWindowButtons: Bool {
        isSidebarVisible || isFloatingSidebarShown || showsCompactSidebar
    }

    /// Margins of the card: none on the side of the sidebar, nor under the bar of the column of icons.
    var cardPaddingEdges: Edge.Set {
        if isSidebarVisible {
            return [.top, .trailing, .bottom]
        }
        return showsCompactSidebar ? [.trailing, .bottom] : .all
    }
}
