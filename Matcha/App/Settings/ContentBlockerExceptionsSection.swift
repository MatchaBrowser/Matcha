import SwiftUI

/// Settings > Privacy: the sites where the blocker is turned off (task 6.2), each with a button to turn it back on
/// there (its open pages reload). Changes made in a private window are not listed.
struct ContentBlockerExceptionsSection: View {
    let service: ContentBlockerService

    var body: some View {
        let sites = service.exceptions.sortedSites
        Section {
            if sites.isEmpty {
                Text("No exceptions.", comment: "Settings > Privacy: the content blocker is active on every website")
                    .foregroundStyle(.secondary)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(sites, id: \.self) { site in
                            row(site)
                        }
                    }
                }
                // Like the permissions list: it scrolls beyond a few rows.
                .scrollDisabled(false)
                .frame(height: min(Double(sites.count) * SitePermissionsSection.rowHeight, SitePermissionsSection.maximumListHeight))
            }
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
            Button {
                service.setException(false, forSite: site)
            } label: {
                Label { removeTitle } icon: { Image(systemName: "trash") }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .help(removeTitle)
            .accessibilityIdentifier("contentBlockerExceptionRemoveButton")
        }
        .frame(height: SitePermissionsSection.rowHeight)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contentBlockerExceptionRow")
    }

    private var removeTitle: Text {
        Text("Block Again", comment: "Settings > Privacy: removes a content blocker exception; ads are blocked again on that website")
    }
}
