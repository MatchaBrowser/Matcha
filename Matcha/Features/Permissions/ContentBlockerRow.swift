import SwiftUI

/// Ligne « Bloquer les publicités et les traqueurs » des réglages du site (tâche 6.2) : le bloqueur sur le site de
/// l'onglet affiché (le domaine et ses sous-domaines). La désactiver met le site en exception, et ses pages ouvertes se
/// rechargent ; dans une fenêtre privée, rien n'est enregistré. Grisée avec une note tant qu'aucune liste n'est prête,
/// ou si le bloqueur est désactivé dans les réglages.
struct ContentBlockerRow: View {
    let tab: BrowserTab
    /// Bloqueur de la session de l'onglet.
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

    /// Vrai si le bloqueur agit sur le site ; toujours faux (grisé) s'il n'est pas disponible.
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

    /// Pourquoi la ligne est grisée.
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
