import AppKit
import OSLog
import SwiftUI

/// Panneau des téléchargements d'une fenêtre, en bas de la barre latérale : il monte au clic sur le bouton du pied (ou
/// par ⌥⌘L), séparé des onglets par un trait. En tête : « Téléchargements », « Effacer » (retire de la liste ce qui
/// n'est plus en cours, sans jamais effacer de fichier ; le panneau reste ouvert) et une croix pour fermer. Fichiers du
/// plus récent au plus ancien ; liste vide : « Aucun téléchargement » et un bouton vers le dossier Téléchargements.
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
                    withAnimation(.easeOut(duration: 0.2)) { downloads.clear(in: scope) }
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
                // Grisé quand il n'y a rien à retirer : liste vide, ou seulement des téléchargements en cours.
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
            if items.isEmpty {
                DownloadsEmptyState()
            } else {
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
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("downloadsPanel")
    }
}

/// Liste vide : « Aucun téléchargement », et un bouton qui ouvre le dossier Téléchargements dans le Finder.
private struct DownloadsEmptyState: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("No Downloads")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("downloadsEmptyState")
            Button("Show Downloads Folder", action: showDownloadsFolder)
                .buttonStyle(.link)
                .font(.caption.weight(.medium))
                .help("Open the Downloads folder in the Finder")
                .accessibilityIdentifier("downloadsShowFolderButton")
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    /// Le vrai dossier Téléchargements de l'utilisateur, jamais le sous-dossier des tests d'interface.
    private func showDownloadsFolder() {
        guard let folder = DownloadLocation.userDownloadsDirectory() else {
            Logger.downloads.error("Dossier Téléchargements introuvable")
            return
        }
        if !NSWorkspace.shared.open(folder) {
            Logger.downloads.error("Dossier Téléchargements non ouvert dans le Finder")
        }
    }
}
