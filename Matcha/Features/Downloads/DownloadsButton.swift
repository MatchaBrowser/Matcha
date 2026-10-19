import SwiftUI

/// “Downloads” button at the bottom of the sidebar, always there, even without downloads: progress ring while a
/// file is arriving, small bounce at each finished file. A click opens or closes the downloads panel, at the bottom
/// of the sidebar (like ⌥⌘L); nothing opens it by itself.
struct DownloadsButton: View {
    @Bindable var model: WindowModel
    let downloads: DownloadManager

    private var scope: DownloadScope {
        model.session.downloadScope
    }

    var body: some View {
        let active = downloads.items(in: scope).filter(\.isActive)
        Button {
            withMotion(.easeOut(duration: 0.2)) { model.isDownloadsPresented.toggle() }
        } label: {
            DownloadsIcon(
                isDownloading: !active.isEmpty,
                fraction: DownloadProgressSummary.overallFraction(of: active.map { ($0.completedBytes, $0.totalBytes) }),
                finishedCount: downloads.finishedCount(in: scope),
            )
        }
        .buttonStyle(SidebarIconButtonStyle())
        .help("Downloads")
        .accessibilityLabel("Downloads")
        .accessibilityIdentifier("downloadsButton")
    }
}

/// Download arrow; during a download, surrounded by a progress ring (pulsing if the size is unknown).
private struct DownloadsIcon: View {
    static let size = 18.0

    let isDownloading: Bool
    let fraction: Double?
    let finishedCount: Int

    var body: some View {
        ZStack {
            if isDownloading {
                Circle()
                    .stroke(Color.primary.opacity(0.2), lineWidth: 2)
                if let fraction {
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.2), value: fraction)
                }
                Image(systemName: "arrow.down")
                    .font(.system(size: 9, weight: .bold))
                    .symbolEffect(.pulse, isActive: fraction == nil)
            } else {
                Image(systemName: "arrow.down.circle")
                    .symbolEffect(.bounce, value: finishedCount)
            }
        }
        .frame(width: Self.size, height: Self.size)
    }
}
