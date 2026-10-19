import SwiftUI

/// Site settings panel of the displayed tab (task 5.2): below the address pill of the sidebar, or at the top of the
/// card below the address bar above the page. Camera and microphone (“Ask”, “Allow”, “Deny”, the profile's
/// decisions), the apps it opens without asking (audit W2), the site's zoom (task 5.4), the blocker on this site (task 6.2, hidden while it
/// is set aside), then
/// the site's cookies and data, cleared (this site only) after confirmation. It follows the displayed tab and never
/// opens or closes by itself (button, ×).
struct SiteSettingsPanel: View {
    let model: WindowModel
    /// Tabs of the Space of the sidebar or card that shows the panel.
    let tabManager: TabManager
    /// Width of the settings in a wide card; the sidebar lets them take its full width.
    var maximumContentWidth = Double.infinity

    private var tab: BrowserTab? {
        tabManager.selectedTab
    }

    var body: some View {
        let origin = SiteOrigin.web(of: tab?.url)
        VStack(alignment: .leading, spacing: 8) {
            header(origin)
            if let origin, let tab, let scope = tabManager.sitePermissions {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SitePermissionKind.allCases) { kind in
                        permissionRow(kind, origin: origin, scope: scope)
                    }
                    // Apps the site opens without asking (audit W2).
                    ForEach(scope.actions(for: origin)) { entry in
                        actionRow(entry, scope: scope)
                    }
                    SiteZoomRow(tab: tab, siteZooms: tabManager.siteZooms)
                    if ContentBlockerService.isAvailable, let contentBlocking = tabManager.contentBlocking {
                        ContentBlockerRow(tab: tab, scope: contentBlocking)
                    }
                    HStack(spacing: 8) {
                        Label {
                            Text("Cookies and Website Data", comment: "Site settings: the cookies and data this website keeps on the Mac")
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "externaldrive")
                        }
                        Spacer(minLength: 8)
                        // Confirmation attached to the window (`SiteDataClearConfirmation`).
                        Button("Clear…") {
                            model.siteDataClearRequest = SiteDataClearRequest(tab: tab, origin: origin)
                        }
                        .controlSize(.small)
                        .fixedSize()
                        .accessibilityIdentifier("siteSettingsClearDataButton")
                    }
                }
                .frame(maxWidth: maximumContentWidth, alignment: .leading)
            } else {
                Text(
                    "This page has no website settings.",
                    comment: "Site settings panel shown for a page that is not a website (empty tab, local file)",
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("siteSettingsPanel")
    }

    /// The site, then the cross.
    private func header(_ origin: SiteOrigin?) -> some View {
        HStack(spacing: 8) {
            if let tab, origin != nil {
                FaviconView(tab: tab, size: 14)
            }
            title(origin)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityIdentifier("siteSettingsTitle")
            Spacer(minLength: 0)
            Button {
                withMotion(.easeOut(duration: 0.2)) { model.isSiteSettingsPresented = false }
            } label: {
                Label { closeTitle } icon: { Image(systemName: "xmark") }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(SidebarIconButtonStyle())
            .help(closeTitle)
            .accessibilityIdentifier("siteSettingsCloseButton")
        }
    }

    /// The site; otherwise the page's short address (local file); without a page, the panel's name.
    private func title(_ origin: SiteOrigin?) -> Text {
        let name = origin?.displayName ?? AddressDisplay.short(for: tab?.url)
        guard !name.isEmpty else {
            return Text("Site Settings", comment: "Button next to the address: permissions and data of the website shown")
        }
        return Text(verbatim: name)
    }

    private var closeTitle: Text {
        Text("Close Site Settings", comment: "Button that closes the site settings panel")
    }

    /// An app the site opens without asking, and the button that makes it ask again.
    private func actionRow(_ entry: SiteActionAllowances.Entry, scope: SitePermissionScope) -> some View {
        HStack(spacing: 8) {
            Label(entry.action.title, systemImage: entry.action.symbolName)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                scope.store.actions.remove(entry)
            } label: {
                SiteActionsSection.forgetTitle
            }
            .controlSize(.small)
            .fixedSize()
            .accessibilityIdentifier("siteSettingsForgetActionButton")
        }
    }

    /// Camera or microphone: “Ask” (no remembered decision), “Allow”, “Deny”.
    private func permissionRow(_ kind: SitePermissionKind, origin: SiteOrigin, scope: SitePermissionScope) -> some View {
        let decision = Binding<SitePermissionDecision?> {
            scope.decision(kind, for: origin)
        } set: {
            scope.set($0, for: kind, origin: origin)
        }
        return HStack(spacing: 8) {
            Label(kind.title, systemImage: kind.symbolName)
                .lineLimit(1)
            Spacer(minLength: 8)
            Picker(kind.title, selection: decision) {
                Text("Ask", comment: "Site settings: the website must ask before using the camera or microphone")
                    .tag(SitePermissionDecision?.none)
                Text("Allow", comment: "Site settings: the website may use the camera or microphone without asking")
                    .tag(SitePermissionDecision?.some(.allow))
                Text("Deny", comment: "Site settings: the website may not use the camera or microphone")
                    .tag(SitePermissionDecision?.some(.deny))
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .controlSize(.small)
            .fixedSize()
            .accessibilityIdentifier("sitePermissionPicker-\(kind.rawValue)")
        }
    }
}
