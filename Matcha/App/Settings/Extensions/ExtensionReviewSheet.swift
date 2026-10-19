import SwiftUI
import WebKit

/// Permissions screen before installing an extension (task 6.4): what it will be able to do, its sites, and the
/// private windows choice (off by default, as before for an update). Nothing is installed without the user's click.
/// An update (same verified publisher) shows the versions and what it adds; a replacement (same name, no proof of the
/// same developer) says that the installed extension's data will be erased (audit E1).
struct ExtensionReviewSheet: View {
    let candidate: ExtensionInstallCandidate
    let install: (_ allowsPrivateWindows: Bool) -> Void
    let cancel: () -> Void

    @State private var allowsPrivateWindows: Bool
    @Environment(\.dismiss) private var dismiss

    init(candidate: ExtensionInstallCandidate, install: @escaping (_ allowsPrivateWindows: Bool) -> Void, cancel: @escaping () -> Void) {
        self.candidate = candidate
        self.install = install
        self.cancel = cancel
        _allowsPrivateWindows = State(initialValue: candidate.allowedPrivateWindows)
    }

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
                    title
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
            if case .replacement = candidate.mode {
                Label {
                    Text(
                        "Matcha can't verify that this file comes from the developer of “\(name)”. Replacing it erases its data.",
                        comment: "Extension install sheet: a file with the name of an installed extension, from an unproven developer",
                    )
                    .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .font(.callout)
                .accessibilityIdentifier("extensionReviewReplacementWarning")
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
                Button {
                    install(allowsPrivateWindows)
                    dismiss()
                } label: {
                    installTitle
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

    private var title: Text {
        switch candidate.mode {
        case .new: Text("Add “\(name)”?")
        case .update: Text("Update “\(name)”?")
        case .replacement:
            Text("Replace “\(name)”?", comment: "Extension install sheet: replaces an installed extension with the same name")
        }
    }

    private var installTitle: Text {
        switch candidate.mode {
        case .new: Text("Add Extension")
        case .update: Text("Update Extension")
        case .replacement:
            Text("Replace Extension", comment: "Button of the extension install sheet: replaces the installed extension, erasing its data")
        }
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
        switch candidate.mode {
        case let .update(previous?), let .replacement(_, previous?):
            return String(
                localized: "Version \(previous) → \(version) · \(origin)",
                comment: "Installed and new versions, and origin, of an extension being updated or replaced",
            )
        default:
            return String(localized: "Version \(version) · \(origin)", comment: "Version and origin of an installed extension")
        }
    }

    @ViewBuilder private var permissions: some View {
        let lines = candidate.isUpdate ? candidate.addedSummary : candidate.summary
        VStack(alignment: .leading, spacing: 8) {
            if lines.isEmpty {
                if candidate.isUpdate {
                    Text("This version doesn't ask for any new permission.", comment: "Extension update sheet: no permission added")
                        .foregroundStyle(.secondary)
                } else {
                    Text("This extension doesn't ask for any special permission.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Text(candidate.isUpdate ? "This version will also be able to:" : "It will be able to:")
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
