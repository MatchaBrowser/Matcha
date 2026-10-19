import AppKit
import OSLog
import SwiftUI

/// Downloads panel of a window, at the bottom of the sidebar: it slides up on a click on the footer button (or with
/// ⌥⌘L), separated from the tabs by a line. At the top: “Downloads”, “Clear” (removes from the list what is no
/// longer in progress, never deleting any file; the panel stays open) and a cross to close it. Files from newest to
/// oldest; empty list: “No Downloads” and a button to the Downloads folder.
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
                    withMotion(.easeOut(duration: 0.2)) { downloads.clear(in: scope) }
                } label: {
                    // Key distinct from the “Clear” of today tabs.
                    Text(String(
                        localized: "Clear Downloads",
                        defaultValue: "Clear",
                        comment: "Button of the downloads list that removes finished, failed and cancelled downloads from the list",
                    ))
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                // Disabled when there is nothing to remove: empty list, or only downloads in progress.
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

/// Empty list: “No Downloads”, and a button that opens the Downloads folder in the Finder.
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

    /// The user's real Downloads folder, never the UI tests' subfolder.
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
