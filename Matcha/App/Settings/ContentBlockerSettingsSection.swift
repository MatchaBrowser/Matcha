import SwiftUI

/// Settings > Privacy: the ad and tracker blocker (task 6.2). The global setting (disabled as long as no list is
/// ready), then each installed list: name, version, rule count, compilation date. The excepted sites and the list
/// credits follow in their own sections.
struct ContentBlockerSettingsSection: View {
    @Bindable var service: ContentBlockerService

    var body: some View {
        Section {
            Toggle(isOn: $service.isEnabled) {
                Text("Block ads and trackers", comment: "Settings > Privacy: turns the content blocker on or off for all websites")
            }
            .disabled(!service.hasLists)
            .accessibilityIdentifier("contentBlockerEnabledToggle")
            if service.hasLists {
                ForEach(service.installedLists) { list in
                    row(list)
                }
            } else {
                Group {
                    if service.state == .loading {
                        Text(
                            "Preparing the blocklists…",
                            comment: "Site settings and Settings > Privacy: the content blocker is not ready yet (launch)",
                        )
                    } else {
                        Text(
                            "No blocklist is installed.",
                            comment: "Site settings and Settings > Privacy: the content blocker has no list, so it is inactive",
                        )
                    }
                }
                .foregroundStyle(.secondary)
            }
        } header: {
            Text("Ads and Trackers", comment: "Settings > Privacy: section of the content blocker")
        } footer: {
            Text(
                "All profiles and private windows, from the next page load. To turn it off for one website, use the site settings.",
                comment: "Settings > Privacy: footer of the content blocker section",
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func row(_ list: ContentBlockerService.InstalledList) -> some View {
        let compiledAt = list.record.compiledAt.formatted(date: .abbreviated, time: .shortened)
        return LabeledContent {
            Text("\(list.record.ruleCount) rules", comment: "Settings > Privacy: number of rules of a blocklist")
                .monospacedDigit()
        } label: {
            Text(verbatim: list.entry.name)
            Text(
                "Version \(list.entry.version), compiled \(compiledAt)",
                comment: "Settings > Privacy: under a blocklist name; first %@ is its version (2026.10.18), second when it was prepared",
            )
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("contentBlockerListRow")
    }
}
