import SwiftUI

/// Settings > Privacy: the decisions remembered per site (camera, microphone), each with a button to forget it
/// (task 5.2). The profile is named as soon as there are several. Private windows are not listed.
struct SitePermissionsSection: View {
    let store: SitePermissionStore
    let profiles: [ProfileRecord]

    var body: some View {
        Section {
            PrivacySiteList(
                items: store.entries,
                empty: Text("No saved decisions.", comment: "Settings > Privacy: no website has a saved camera or microphone decision"),
                row: row,
            )
        } header: {
            Text("Website Permissions", comment: "Settings > Privacy: section listing the saved camera and microphone decisions")
        } footer: {
            Text(
                "Saved with “Always Allow” or “Don't Allow”, or in the site settings next to the address. Never in private windows.",
                comment: "Settings > Privacy: footer of the website permissions list",
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func row(_ entry: SitePermissionEntry) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: entry.origin.displayName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if profiles.count > 1, let name = profiles.first(where: { $0.id == entry.profileID })?.name {
                    Text(verbatim: name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            Label(entry.kind.title, systemImage: entry.kind.symbolName)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
            Text(verbatim: entry.decision.stateTitle)
                .frame(minWidth: 70, alignment: .trailing)
            PrivacySiteRemoveButton(title: forgetTitle, identifier: "sitePermissionForgetButton") { store.remove(entry) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sitePermissionRow")
    }

    private var forgetTitle: Text {
        Text("Forget Decision", comment: "Settings > Privacy: removes a saved camera or microphone decision; the website will ask again")
    }
}
