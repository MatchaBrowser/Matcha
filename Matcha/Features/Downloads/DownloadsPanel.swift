import SwiftUI

/// Panneau des téléchargements d'une fenêtre, en bas de la barre latérale : il monte au clic sur le bouton du pied,
/// séparé des onglets par un trait. En tête : « Téléchargements », « Effacer » (retire de la liste ce qui n'est plus
/// en cours, sans jamais effacer de fichier) et une croix pour fermer. Fichiers du plus récent au plus ancien.
struct DownloadsPanel: View {
    static let maximumListHeight = 280.0

    let downloads: DownloadManager
    let scope: DownloadScope
    let close: () -> Void

    var body: some View {
        let items = downloads.items(in: scope)
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Text("Downloads")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
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
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .disabled(items.allSatisfy(\.isActive))
                .help("Remove finished downloads from the list. Files stay in the Downloads folder.")
                .accessibilityIdentifier("downloadsClearButton")
                Button(action: close) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(SidebarIconButtonStyle())
                .help("Close Downloads")
                .accessibilityLabel(Text("Close Downloads"))
                .accessibilityIdentifier("downloadsCloseButton")
            }
            .padding(.top, 8)
            .padding(.bottom, 4)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items) { item in
                        DownloadRow(item: item, downloads: downloads)
                    }
                }
            }
            .scrollIndicators(.never)
            .frame(height: min(Double(items.count) * DownloadRow.height, Self.maximumListHeight))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("downloadsPanel")
    }
}
