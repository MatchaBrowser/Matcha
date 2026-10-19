import SwiftUI

/// Sidebar, from top to bottom: navigation, address (zoom badge, site settings button), extension buttons, site
/// settings panel if it is open, favorites, pinned, new tab, today tabs, downloads panel if it is open, Spaces
/// (and on the left, the downloads button, always there).
struct SidebarView: View {
    let model: WindowModel
    let tabManager: TabManager
    /// Opens the command bar on the address of the displayed tab (click on the pill).
    let editAddress: () -> Void
    let newTab: () -> Void
    /// False when the address bar is above the page: the sidebar then has neither an address
    /// nor navigation buttons.
    var showsAddressBar = true
    var showsNavigationButtons = true
    /// Action of the Home button; nil to not display it.
    var goHome: (() -> Void)?
    /// Button that hides or shows the sidebar, next to the window's buttons.
    var sidebarToggle: SidebarToggle?

    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsAddressBar {
                SidebarTopBar(
                    tab: tabManager.selectedTab,
                    showsNavigationButtons: showsNavigationButtons,
                    goHome: goHome,
                    sidebarToggle: sidebarToggle,
                )
                // Zoom badge of the selected tab, even when a Peek is open (it has its own).
                HStack(spacing: 4) {
                    AddressPill(tab: tabManager.selectedTab, edit: editAddress)
                    ZoomBadge(page: tabManager.selectedTab, siteZooms: tabManager.siteZooms)
                    SiteSettingsButton(tab: tabManager.selectedTab, isPresented: model.isSiteSettingsPresented) {
                        setSiteSettingsPresented(!model.isSiteSettingsPresented)
                    }
                }
                .animatesZoomBadge(of: tabManager.selectedTab)
                // Extension buttons (task 6.5): they target the page in front (the Peek if it is open).
                ExtensionButtonsRow(tab: tabManager.frontTab, isPrivate: model.session.isPrivate)
                if model.isSiteSettingsPresented {
                    VStack(spacing: 0) {
                        SiteSettingsPanel(model: model, tabManager: tabManager)
                        Divider()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            } else {
                SidebarTopBar(tab: tabManager.selectedTab, showsNavigationButtons: false, sidebarToggle: sidebarToggle)
            }
            FavoritesGrid(tabManager: tabManager)
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    PinnedSection(tabManager: tabManager)
                    TodaySection(tabManager: tabManager, newTab: newTab)
                }
            }
            .scrollIndicators(.never)
            // Right click on the sidebar's background; the rows have their own menu.
            .contextMenu {
                Button("New Folder") { tabManager.newFolder() }
            }
            // Opened even when empty: it says so, and leads to the Downloads folder.
            if model.isDownloadsPresented {
                DownloadsPanel(downloads: downloads, scope: model.session.downloadScope) {
                    withAnimation(.easeOut(duration: 0.2)) { model.isDownloadsPresented = false }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            SpaceSwitcher(model: model)
                .overlay(alignment: .leading) {
                    DownloadsButton(model: model, downloads: downloads)
                }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    /// The site settings panel slides below the pill and pushes the tabs down.
    private func setSiteSettingsPresented(_ isPresented: Bool) {
        withAnimation(.easeOut(duration: 0.2)) { model.isSiteSettingsPresented = isPresented }
    }
}
