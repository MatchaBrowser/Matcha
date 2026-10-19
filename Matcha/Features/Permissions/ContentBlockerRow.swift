import SwiftUI

/// “Block Ads and Trackers” row of the site settings (task 6.2): the blocker on the displayed tab's site (the
/// domain and its subdomains). Turning it off adds the site to the exceptions, and its open pages reload; in a
/// private window, nothing is saved. Disabled with a note as long as no list is ready, or if the blocker is turned
/// off in the settings.
struct ContentBlockerRow: View {
    let tab: BrowserTab
    /// Blocker of the tab's session.
    let scope: ContentBlockerScope

    private var site: String? {
        ContentBlockerExceptions.site(for: tab.url)
    }

    var body: some View {
        let site = site
        let service = scope.service
        let isAvailable = service.hasLists && service.isEnabled && site != nil
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Label {
                    title
                } icon: {
                    Image(systemName: "shield.lefthalf.filled")
                }
                .lineLimit(1)
                Spacer(minLength: 8)
                Toggle(isOn: blocks(on: site, isAvailable: isAvailable)) { title }
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .disabled(!isAvailable)
                    .accessibilityIdentifier("contentBlockerSiteToggle")
            }
            if let note = note(service) {
                note
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contentBlockerRow")
    }

    private var title: Text {
        Text("Block Ads and Trackers", comment: "Site settings: switch that turns the content blocker on or off for this website")
    }

    /// True if the blocker acts on the site; always false (disabled) if it is not available.
    private func blocks(on site: String?, isAvailable: Bool) -> Binding<Bool> {
        Binding {
            guard isAvailable, let site else {
                return false
            }
            return !scope.isExcepted(site: site)
        } set: { blocks in
            if let site {
                scope.setBlocks(blocks, onSite: site)
            }
        }
    }

    /// Why the row is disabled.
    private func note(_ service: ContentBlockerService) -> Text? {
        if service.state == .loading {
            return Text(
                "Preparing the blocklists…",
                comment: "Site settings and Settings > Privacy: the content blocker is not ready yet (launch)",
            )
        }
        if !service.hasLists {
            return Text(
                "No blocklist is installed.",
                comment: "Site settings and Settings > Privacy: the content blocker has no list, so it is inactive",
            )
        }
        if !service.isEnabled {
            return Text(
                "Turned off in Settings > Privacy.",
                comment: "Site settings: the content blocker is turned off for all websites in the app settings",
            )
        }
        return nil
    }
}
