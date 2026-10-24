import SwiftUI

/// Hidden sidebar reduced to icons (Settings > Appearance): the bar across the top and the column of icons. Hovering
/// the column shows the whole sidebar over the page, like the left edge when the sidebar is hidden completely.
extension BrowserWindowView {
    /// Wait before the sidebar shows: a click on an icon in passing stays a click.
    static let compactRevealDelay = Duration.milliseconds(400)

    /// Bar above the column of icons.
    var compactTopBar: some View {
        CompactTopBar(
            tab: model.selectedTab,
            showsAddress: addressBarPosition == .sidebar,
            showsNavigationButtons: showsNavigationButtons,
            goHome: homeButtonAction,
            sidebarToggle: SidebarToggle(isVisible: isSidebarVisible, toggle: toggleSidebar),
            editAddress: editAddress,
        )
    }

    var compactSidebar: some View {
        CompactSidebar(model: model, tabManager: tabManager, newTab: openCommandBarForNewTab, showDownloads: toggleDownloads)
            .onHover(perform: revealSidebar(hovering:))
    }

    /// The pointer enters the column: the floating sidebar shows after `compactRevealDelay`, unless it leaves before.
    /// It closes as the pointer leaves it (`FloatingSidebar`).
    func revealSidebar(hovering: Bool) {
        compactRevealTask?.cancel()
        compactRevealTask = nil
        guard hovering else {
            return
        }
        compactRevealTask = Task { @MainActor in
            try? await Task.sleep(for: Self.compactRevealDelay)
            guard !Task.isCancelled else {
                return
            }
            withMotion(.easeOut(duration: 0.15)) { isFloatingSidebarHovered = true }
        }
    }
}
