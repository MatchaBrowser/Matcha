import SwiftUI

/// Settings > Privacy: the sites where the blocker is turned off (task 6.2), each with a button to turn it back on
/// there (its open pages reload). Changes made in a private window are not listed.
struct ContentBlockerExceptionsSection: View {
    let service: ContentBlockerService

    var body: some View {
        Section {
            PrivacySiteList(
                items: service.exceptions.sortedSites,
                id: \.self,
                empty: Text("No exceptions.", comment: "Settings > Privacy: the content blocker is active on every website"),
                row: row,
            )
        } header: {
            Text("Blocker Exceptions", comment: "Settings > Privacy: section listing the websites where the content blocker is off")
        } footer: {
            Text(
                "Websites where you turned off the blocker in the site settings, with their subdomains. Never from private windows.",
                comment: "Settings > Privacy: footer of the content blocker exceptions",
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func row(_ site: String) -> some View {
        HStack(spacing: 8) {
            Text(verbatim: site)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            PrivacySiteRemoveButton(title: removeTitle, identifier: "contentBlockerExceptionRemoveButton") {
                service.setException(false, forSite: site)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contentBlockerExceptionRow")
    }

    private var removeTitle: Text {
        Text("Block Again", comment: "Settings > Privacy: removes a content blocker exception; ads are blocked again on that website")
    }
}
