import SwiftUI

/// Rounded-corner card of a pane: the tab's page, with the address bar above if the settings place it there (and
/// below it, the site settings panel), then the find bar and the page's permission request banner. A tab that has not
/// loaded anything yet, or the absence of a tab, shows a welcome view; a tab woken from sleep shows its snapshot while
/// it reloads; a page that crashed several times in a row, a message to reload it.
struct PageCard: View {
    let tab: BrowserTab?
    /// Active pane of a split: border in the accent color.
    let isMarked: Bool
    /// Selected tab (only pane, or active pane of a split): it carries the site settings panel.
    var isActive = true
    let addressBarPosition: AddressBarPosition
    let showsNavigationButtons: Bool
    /// Action of the Home button; nil to hide it.
    var goHome: (() -> Void)?
    /// Opens the command bar on the address of the displayed tab.
    let editAddress: () -> Void
    /// Makes this pane active (click in its address bar or on its welcome view).
    let activate: () -> Void
    /// Receiver of sidebar items dropped on the page.
    var sidebarDropTarget: (any SidebarItemDropTarget)?
    /// Per-site zoom of the window (zoom badge of the address bar above the page).
    var siteZooms: SiteZoomStore?

    @Environment(WindowModel.self) private var windowModel: WindowModel?

    var body: some View {
        VStack(spacing: 0) {
            if addressBarPosition == .top {
                // Pill and Home target the selected tab: this pane becomes active first.
                AddressToolbar(
                    tab: tab,
                    editAddress: {
                        activate()
                        editAddress()
                    },
                    showsNavigationButtons: showsNavigationButtons,
                    goHome: goHome.map { home in
                        {
                            activate()
                            home()
                        }
                    },
                    isSiteSettingsPresented: showsSiteSettings,
                    toggleSiteSettings: toggleSiteSettings,
                    siteZooms: siteZooms,
                    isPrivate: windowModel?.session.isPrivate ?? false,
                )
                .simultaneousGesture(TapGesture().onEnded { activate() })
                Divider()
                if showsSiteSettings, let windowModel {
                    SiteSettingsPanel(model: windowModel, tabManager: windowModel.space.tabManager, maximumContentWidth: 320)
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Divider()
                }
            }
            // Find in page (task 5.3), then permission requests (task 5.2): bar and banner push the page down. The
            // bar stays at the top: an incoming banner does not move the field being typed in.
            if let tab {
                FindBar(page: tab, activate: activate)
                PermissionBanner(prompts: tab.permissionPrompts)
            }
            page
                // Area that the peek (Shift-click) dims, below the address bar (task 4.4).
                .anchorPreference(key: PeekPageAreas.self, value: .bounds) { [$0] }
        }
        .background(.background)
        .clipShape(.rect(cornerRadius: BrowserWindowView.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BrowserWindowView.cardCornerRadius)
                .strokeBorder(
                    isMarked ? AnyShapeStyle(Color.accentColor.opacity(0.7)) : AnyShapeStyle(.hairline),
                    lineWidth: isMarked ? 2 : 1,
                )
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: tab?.displayTitle ?? ""))
        .accessibilityValue(accessibilityValue)
        .accessibilityIdentifier("pagePane")
    }

    /// Site settings panel open in the window, shown on the card of the selected tab.
    private var showsSiteSettings: Bool {
        isActive && windowModel?.isSiteSettingsPresented == true
    }

    /// On the active pane, opens or closes the panel; on another pane of a split, makes it active and opens it there.
    private func toggleSiteSettings() {
        let isPresented = isActive ? !(windowModel?.isSiteSettingsPresented ?? false) : true
        activate()
        withMotion(.easeOut(duration: 0.2)) { windowModel?.isSiteSettingsPresented = isPresented }
    }

    /// “Active Pane” on the active pane of a split.
    private var accessibilityValue: Text {
        isMarked ? Text("Active Pane", comment: "Accessibility value of the active page in a split view") : Text(verbatim: "")
    }

    /// Page of the tab, or the welcome view.
    @ViewBuilder private var page: some View {
        if let tab, tab.url != nil, let webView = tab.webView {
            WebView(webView: webView, sidebarDropTarget: sidebarDropTarget)
                .id(ObjectIdentifier(webView))
                // Tab woken from sleep (task 5.6): its snapshot, while the page reloads. It is there from the first
                // render (no blank page) and fades out.
                .overlay {
                    if let cover = tab.suspension.cover {
                        SuspendedPageCover(cover: cover)
                            .transition(.asymmetric(insertion: .identity, removal: .opacity))
                    }
                }
                .animation(.easeOut(duration: 0.2), value: tab.suspension.cover == nil)
                // Page process stopped several times in a row (task 5.7): the message, until the reload.
                .overlay {
                    if tab.crash.isShowingProblem {
                        PageProblemView(page: tab, activate: activate)
                    }
                }
                // Load that failed (audit K5): why, until another load.
                .overlay {
                    if let error = tab.loadFailure.error {
                        PageLoadErrorView(page: tab, error: error, activate: activate)
                    }
                }
        } else {
            ContentUnavailableView(emptyPageTitle, systemImage: "globe", description: Text(emptyPageDescription))
                // Takes the full height, like the web view: otherwise the whole column is centered vertically.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture(perform: activate)
        }
    }

    /// Title of the welcome view: no tab, or a tab that has not loaded anything yet.
    private var emptyPageTitle: LocalizedStringKey {
        tab == nil ? "No Tabs" : "New Tab"
    }

    /// Without a tab, ⌘T opens one; an empty tab is filled with ⌘L.
    private var emptyPageDescription: LocalizedStringKey {
        tab == nil ? "Press ⌘T to search or enter an address." : "Press ⌘L to search or enter an address."
    }
}
