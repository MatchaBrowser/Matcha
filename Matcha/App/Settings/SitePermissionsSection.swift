import SwiftUI

/// Réglages > Confidentialité : les décisions retenues par site (caméra, micro), chacune avec un bouton pour
/// l'oublier (tâche 5.2). Le profil est nommé dès qu'il y en a plusieurs. Les fenêtres privées n'y figurent pas.
struct SitePermissionsSection: View {
    static let rowHeight = 30.0
    static let maximumListHeight = 210.0

    let store: SitePermissionStore
    let profiles: [ProfileRecord]

    var body: some View {
        let entries = store.entries
        Section {
            if entries.isEmpty {
                Text("No saved decisions.", comment: "Settings > Privacy: no website has a saved camera or microphone decision")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(entries) { entry in
                            row(entry)
                        }
                    }
                }
                // La fenêtre des réglages prend la hauteur de son contenu : la liste défile au-delà de quelques lignes.
                .scrollDisabled(false)
                .frame(height: min(Double(entries.count) * Self.rowHeight, Self.maximumListHeight))
            }
        } header: {
            Text("Website Permissions", comment: "Settings > Privacy: section listing the saved camera and microphone decisions")
        } footer: {
            Text(
                "Saved with “Always Allow” or “Don't Allow”, or in the site settings next to the address. Never in private windows.",
                comment: "Settings > Privacy: footer of the website permissions list",
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func row(_ entry: SitePermissionEntry) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: entry.origin.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if profiles.count > 1, let name = profiles.first(where: { $0.id == entry.profileID })?.name {
                    Text(verbatim: name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Label(entry.kind.title, systemImage: entry.kind.symbolName)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
            Text(verbatim: entry.decision.stateTitle)
                .frame(minWidth: 70, alignment: .trailing)
            Button {
                store.remove(entry)
            } label: {
                Label { forgetTitle } icon: { Image(systemName: "trash") }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(forgetTitle)
            .accessibilityIdentifier("sitePermissionForgetButton")
        }
        .frame(height: Self.rowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sitePermissionRow")
    }

    private var forgetTitle: Text {
        Text("Forget Decision", comment: "Settings > Privacy: removes a saved camera or microphone decision; the website will ask again")
    }
}
