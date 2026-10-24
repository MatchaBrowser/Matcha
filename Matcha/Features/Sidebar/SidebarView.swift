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
                    tab: model.selectedTab,
                    showsNavigationButtons: showsNavigationButtons,
                    goHome: goHome,
                    sidebarToggle: sidebarToggle,
                )
                // Zoom badge of the selected tab, even when a Peek is open (it has its own).
                HStack(spacing: 4) {
                    AddressPill(tab: model.selectedTab, edit: editAddress)
                    ZoomBadge(page: model.selectedTab, siteZooms: tabManager.siteZooms)
                    SiteSettingsButton(tab: model.selectedTab, isPresented: model.isSiteSettingsPresented) {
                        setSiteSettingsPresented(!model.isSiteSettingsPresented)
                    }
                }
                .animatesZoomBadge(of: model.selectedTab)
                // Extension buttons (task 6.5): they target the page in front (the Peek if it is open).
                ExtensionButtonsRow(tab: model.frontTab, isPrivate: model.session.isPrivate)
                if model.isSiteSettingsPresented {
                    VStack(spacing: 0) {
                        SiteSettingsPanel(model: model, tabManager: tabManager)
                        Divider()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            } else {
                SidebarTopBar(tab: model.selectedTab, showsNavigationButtons: false, sidebarToggle: sidebarToggle)
            }
            if model.windowTabs == nil {
                spaceTabs
            } else {
                // A window of its own tabs (detached tab): only them, as in Arc's “This Window”.
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        TodaySection(tabManager: tabManager, newTab: newTab) { WindowTabsHeader(model: model) }
                    }
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(Text(
                        "This Window",
                        comment: "Sidebar title of a window holding only its own tabs, outside any Space",
                    ))
                }
                .scrollIndicators(.never)
            }
            // Opened even when empty: it says so, and leads to the Downloads folder.
            if model.isDownloadsPresented {
                DownloadsPanel(downloads: downloads, scope: model.session.downloadScope) {
                    withMotion(.easeOut(duration: 0.2)) { model.isDownloadsPresented = false }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            footer
                .overlay(alignment: .leading) {
                    DownloadsButton(model: model, downloads: downloads)
                }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    /// Favorites, pinned tabs and today tabs of the displayed Space.
    @ViewBuilder private var spaceTabs: some View {
        // Each section is a group named for VoiceOver (audit H3).
        FavoritesGrid(tabManager: tabManager)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Favorites"))
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                VStack(alignment: .leading, spacing: 2) {
                    PinnedSection(tabManager: tabManager)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Pinned", comment: "VoiceOver: section of the pinned tabs in the sidebar"))
                VStack(alignment: .leading, spacing: 2) {
                    TodaySection(tabManager: tabManager, newTab: newTab)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("Today", comment: "VoiceOver: section of the Today tabs in the sidebar"))
            }
        }
        .scrollIndicators(.never)
        // Right click on the sidebar's background; the rows have their own menu.
        .contextMenu {
            Button("New Folder") { tabManager.newFolder() }
        }
    }

    /// The Spaces; none in a window of its own tabs, which only keeps the downloads button.
    @ViewBuilder private var footer: some View {
        if model.windowTabs == nil {
            SpaceSwitcher(model: model)
        } else {
            Color.clear
                .frame(height: 28)
        }
    }

    /// The site settings panel slides below the pill and pushes the tabs down.
    private func setSiteSettingsPresented(_ isPresented: Bool) {
        withMotion(.easeOut(duration: 0.2)) { model.isSiteSettingsPresented = isPresented }
    }
}
