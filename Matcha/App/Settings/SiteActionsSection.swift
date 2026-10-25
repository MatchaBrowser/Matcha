import SwiftUI

/// Settings > Privacy: what websites may do without asking, answered “Always” in the page's banner (open another app,
/// download files: audits W2 and W7), each with a button to forget it. The profile is named as soon as there are several. Private windows
/// are not listed.
struct SiteActionsSection: View {
    let store: SiteActionAllowances
    let profiles: [ProfileRecord]

    var body: some View {
        Section {
            PrivacySiteList(
                items: store.sortedEntries,
                empty: Text(
                    "No website opens apps or downloads files without asking.",
                    comment: "Settings > Privacy: no website may open an app or download files without asking",
                ),
                row: row,
            )
        } header: {
            Text("Allowed Without Asking", comment: "Settings > Privacy: websites that may open an app or download files without asking")
        } footer: {
            Text(
                "Saved with “Always Open” or “Always Allow” when a website asks. Never in private windows.",
                comment: "Settings > Privacy: footer of the list of websites that may open an app or download files without asking",
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func row(_ entry: SiteActionAllowances.Entry) -> some View {
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
            Label(entry.action.title, systemImage: entry.action.symbolName)
                .labelStyle(.titleAndIcon)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            PrivacySiteRemoveButton(title: Self.forgetTitle, identifier: "siteActionForgetButton") { store.remove(entry) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("siteActionRow")
    }

    static var forgetTitle: Text {
        Text("Ask Again", comment: "Forgets that a website may open an app or download files without asking: it will ask again")
    }
}
