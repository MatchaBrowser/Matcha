import SwiftUI
import WebKit

/// One line of the permissions screen: symbol and sentence (and the list of sites).
struct ExtensionPermissionLineView: View {
    let line: ExtensionPermissionSummary.Line

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
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

    private var title: LocalizedStringKey {
        switch line {
        case .allWebsites: "Read and change your data on all websites"
        case .websites: "Read and change your data on these websites:"
        case .browsingHistory: "Read your browsing history"
        case .cookies: "Read and change website cookies"
        case .clipboardRead: "Read data you copy and paste"
        case .clipboardWrite: "Change data you copy and paste"
        case .blockContent: "Block content on websites"
        case .nativeApps: "Communicate with apps on your Mac"
        case .notifications: "Show notifications"
        case .downloads: "Manage your downloads"
        case .bookmarks: "Read and change your bookmarks"
        case .location: "Detect your location"
        case .localFiles: "Read your local files"
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
