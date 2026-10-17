import SwiftUI

/// Liste des téléchargements d'une fenêtre, du plus récent au plus ancien, ouverte par le bouton de la barre latérale.
/// « Effacer » retire de la liste ce qui n'est plus en cours, sans jamais effacer de fichier.
struct DownloadsPopover: View {
    static let width = 340.0
    static let maximumListHeight = 360.0

    let downloads: DownloadManager
    let scope: DownloadScope
    /// Ferme la liste (plus rien à montrer après « Effacer »).
    let close: () -> Void

    var body: some View {
        let items = downloads.items(in: scope)
        VStack(spacing: 0) {
            HStack {
                Text("Downloads")
                    .font(.headline)
                Spacer()
                Button {
                    downloads.clear(in: scope)
                    if downloads.items(in: scope).isEmpty {
                        close()
                    }
                } label: {
                    // Clé distincte du « Clear » des onglets du jour.
                    Text(String(
                        localized: "Clear Downloads",
                        defaultValue: "Clear",
                        comment: "Button of the downloads list that removes finished, failed and cancelled downloads from the list",
                    ))
                }
                .buttonStyle(.borderless)
                .disabled(items.allSatisfy(\.isActive))
                .help("Remove finished downloads from the list. Files stay in the Downloads folder.")
                .accessibilityIdentifier("downloadsClearButton")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            Divider()
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        DownloadRow(item: item, downloads: downloads)
                    }
                }
            }
            .frame(height: min(Double(items.count) * DownloadRow.height, Self.maximumListHeight))
        }
        .frame(width: Self.width)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("downloadsPopover")
    }
}
