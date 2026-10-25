import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Row of the downloads list: icon, name, progress or state, and its buttons (cancel during the download, show in
/// the Finder afterwards). A finished file opens with a double-click, its menu or VoiceOver's “Open” action (review
/// IU19). A file deleted or moved since is “not found”: no button and nothing to open.
struct DownloadRow: View {
    static let height = 58.0

    let item: DownloadItem
    let downloads: DownloadManager

    /// Icon of the file, looked up once per state rather than at each drawing (review IU6).
    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                } else {
                    Color.clear
                }
            }
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
        .onTapGesture(count: 2) { openFile() }
        .contextMenu {
            if let url = openableURL {
                Button(Self.openTitle) { NSWorkspace.shared.open(url) }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
        .task(id: iconKey) { icon = makeIcon() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: item.fileName))
        .accessibilityActions {
            if openableURL != nil {
                Button(Self.openTitle) { openFile() }
            }
        }
        .accessibilityIdentifier("downloadRow")
    }

    private static let openTitle = String(
        localized: "Open Download",
        defaultValue: "Open",
        comment: "Menu and VoiceOver action of a finished download: opens the file",
    )

    /// The finished file, if it is still there.
    private var openableURL: URL? {
        item.state == .finished && !item.isFileMissing ? item.destinationURL : nil
    }

    private func openFile() {
        if let url = openableURL {
            NSWorkspace.shared.open(url)
        }
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
            if !item.isFileMissing, let url = item.destinationURL {
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

    private var status: String {
        Self.status(of: item)
    }

    /// “12 MB of 40 MB” during the download, the size once finished (or “File not found”), otherwise the state.
    static func status(of item: DownloadItem) -> String {
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
            if item.isFileMissing {
                return String(localized: "File not found", comment: "State of a finished download whose file was deleted or moved")
            }
            return DownloadProgressSummary.byteCount(item.completedBytes)
        case .failed:
            return String(localized: "Failed", comment: "State of a download that failed")
        case .cancelled:
            return String(localized: "Cancelled", comment: "State of a download cancelled by the user")
        }
    }

    /// What the icon depends on.
    private var iconKey: String {
        "\(item.state) \(item.isFileMissing) \(item.fileName)"
    }

    /// Icon of the finished file (an app's own icon for an app), otherwise that of its type.
    private func makeIcon() -> NSImage {
        if let url = openableURL {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        let pathExtension = DownloadFileName.split(item.fileName).extension.dropFirst()
        return NSWorkspace.shared.icon(for: UTType(filenameExtension: String(pathExtension)) ?? .data)
    }
}

private extension View {
    /// Round button of the row, icon only.
    func rowIconButton() -> some View {
        labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .font(.system(size: 16))
            .foregroundStyle(.secondary)
    }
}
