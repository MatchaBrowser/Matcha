import SwiftUI
import WebKit

/// One line of the permissions screen: symbol and sentence (and the list of sites).
struct ExtensionPermissionLineView: View {
    let line: ExtensionPermissionSummary.Line

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: line.title)
                if case let .websites(hosts) = line {
                    Text(verbatim: hosts.joined(separator: ", "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
            }
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(.secondary)
                .frame(width: 18)
        }
    }

    private var symbol: String {
        switch line {
        case .allWebsites, .websites: "globe"
        case .browsingHistory: "clock.arrow.circlepath"
        case .cookies: "externaldrive"
        case .clipboardRead, .clipboardWrite: "doc.on.clipboard"
        case .blockContent: "hand.raised"
        case .nativeApps: "macwindow"
        case .notifications: "bell"
        case .downloads: "arrow.down.circle"
        case .bookmarks: "bookmark"
        case .location: "location"
        case .localFiles: "folder"
        }
    }
}
