import SwiftUI

/// Réglages > Confidentialité : crédits des listes de blocage livrées (tâche 6.2), lus dans leur manifeste : nom,
/// licence et site de chaque liste. La tâche 6.1 donne ces informations avec les listes.
struct BlocklistCreditsSection: View {
    let service: ContentBlockerService

    var body: some View {
        Section {
            if service.installedLists.isEmpty {
                Text(
                    "The authors and licenses of the blocklists appear here.",
                    comment: "Settings > Privacy: placeholder of the blocklist credits when no list is installed",
                )
                .foregroundStyle(.secondary)
            } else {
                ForEach(service.installedLists) { list in
                    row(list.entry)
                }
            }
        } header: {
            Text("Blocklist Credits", comment: "Settings > Privacy: section crediting the authors and licenses of the blocklists")
        }
    }

    private func row(_ entry: BlocklistEntry) -> some View {
        LabeledContent {
            if let url = entry.homepageURL {
                Link(destination: url) {
                    Text(verbatim: url.host() ?? url.absoluteString)
                }
            }
        } label: {
            Text(verbatim: entry.name)
            if let license = entry.license {
                Text(verbatim: license)
            }
        }
        .accessibilityIdentifier("blocklistCreditRow")
    }
}
