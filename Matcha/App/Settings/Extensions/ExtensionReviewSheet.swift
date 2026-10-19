import SwiftUI
import WebKit

/// Permissions screen before installing an extension (task 6.4): what it will be able to do, its sites, and the
/// private windows choice (off by default). Nothing is installed without “Add Extension”.
struct ExtensionReviewSheet: View {
    let candidate: ExtensionInstallCandidate
    let install: (_ allowsPrivateWindows: Bool) -> Void
    let cancel: () -> Void

    @State private var allowsPrivateWindows = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let webExtension = candidate.webExtension
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                if let icon = webExtension.icon(for: CGSize(width: 48, height: 48)) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 48, height: 48)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(candidate.isUpdate ? "Update “\(name)”?" : "Add “\(name)”?")
                        .font(.headline)
                        .accessibilityIdentifier("extensionReviewTitle")
                    Text(details)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let description = webExtension.displayDescription, !description.isEmpty {
                        Text(verbatim: description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                            .padding(.top, 2)
                    }
                }
            }
            Divider()
            permissions
            Toggle("Allow in Private Windows", isOn: $allowsPrivateWindows)
                .accessibilityIdentifier("extensionReviewPrivateToggle")
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) {
                    cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button(candidate.isUpdate ? "Update Extension" : "Add Extension") {
                    install(allowsPrivateWindows)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("extensionReviewAddButton")
            }
        }
        .padding(20)
        .frame(width: 440)
        .interactiveDismissDisabled()
    }

    private var name: String {
        candidate.webExtension.displayName ?? candidate.identifier
    }

    /// “Version 1.2 · In Proton Pass for Safari” or “Version 1.2 · darkreader.crx”.
    private var details: String {
        let origin = switch candidate.source {
        case let .appExtension(appExtension):
            String(localized: "In \(appExtension.appName)", comment: "App that contains a Safari extension, e.g. In Proton Pass for Safari")
        case let .package(_, _, fileName):
            fileName
        }
        guard let version = candidate.webExtension.displayVersion ?? candidate.webExtension.version else {
            return origin
        }
        return String(localized: "Version \(version) · \(origin)", comment: "Version and origin of an installed extension")
    }

    @ViewBuilder private var permissions: some View {
        let lines = candidate.summary
        VStack(alignment: .leading, spacing: 8) {
            if lines.isEmpty {
                Text("This extension doesn't ask for any special permission.")
                    .foregroundStyle(.secondary)
            } else {
                Text("It will be able to:")
                    .font(.subheadline.weight(.semibold))
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    ExtensionPermissionLineView(line: line)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("extensionReviewPermissions")
    }
}

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
        }
    }
}
