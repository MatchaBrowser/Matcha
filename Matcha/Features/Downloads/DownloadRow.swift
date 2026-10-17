import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Ligne de la liste des téléchargements : icône, nom, progression ou état, et ses boutons (annuler pendant le
/// téléchargement, afficher dans le Finder ensuite). Un double-clic sur un fichier terminé l'ouvre : seul geste qui
/// ouvre un fichier téléchargé.
struct DownloadRow: View {
    static let height = 58.0

    let item: DownloadItem
    let downloads: DownloadManager

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: item.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if item.isActive {
                    progressBar
                }
                Text(status)
                    .font(.caption)
                    .foregroundStyle(item.state == .failed ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                    .help(item.failureReason ?? "")
                    .accessibilityIdentifier("downloadStatus")
            }
            Spacer(minLength: 0)
            actionButton
        }
        .padding(.horizontal, 4)
        .frame(height: Self.height)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            if item.state == .finished, let url = item.destinationURL {
                NSWorkspace.shared.open(url)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: item.fileName))
        .accessibilityIdentifier("downloadRow")
    }

    @ViewBuilder private var progressBar: some View {
        if let fraction = item.fractionCompleted {
            ProgressView(value: fraction)
                .controlSize(.small)
        } else {
            ProgressView()
                .progressViewStyle(.linear)
                .controlSize(.small)
        }
    }

    @ViewBuilder private var actionButton: some View {
        switch item.state {
        case .downloading:
            Button("Cancel", systemImage: "xmark.circle.fill") {
                downloads.cancel(item)
            }
            .rowIconButton()
            .help("Cancel")
            .accessibilityIdentifier("downloadCancelButton")
        case .finished:
            if let url = item.destinationURL {
                Button("Show in Finder", systemImage: "magnifyingglass.circle.fill") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                .rowIconButton()
                .help("Show in Finder")
                .accessibilityIdentifier("downloadShowInFinderButton")
            }
        case .failed, .cancelled:
            EmptyView()
        }
    }

    /// « 12 Mo sur 40 Mo » pendant le téléchargement, la taille une fois terminé, sinon l'état.
    private var status: String {
        switch item.state {
        case .downloading:
            let completed = DownloadProgressSummary.byteCount(item.completedBytes)
            guard let total = item.totalBytes else {
                return completed
            }
            let size = DownloadProgressSummary.byteCount(total)
            return String(
                localized: "\(completed) of \(size)",
                comment: "Progress of a download: bytes received of the total size, e.g. 12 MB of 40 MB",
            )
        case .finished:
            return DownloadProgressSummary.byteCount(item.completedBytes)
        case .failed:
            return String(localized: "Failed", comment: "State of a download that failed")
        case .cancelled:
            return String(localized: "Cancelled", comment: "State of a download cancelled by the user")
        }
    }

    /// Icône du fichier terminé (celle d'une app pour une app), sinon celle de son type.
    private var icon: NSImage {
        if item.state == .finished, let url = item.destinationURL, FileManager.default.fileExists(atPath: url.path) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let pathExtension = DownloadFileName.split(item.fileName).extension.dropFirst()
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: String(pathExtension)) ?? .data)
    }
}

private extension View {
    /// Bouton rond de la ligne, icône seule.
    func rowIconButton() -> some View {
        labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
    }
}
