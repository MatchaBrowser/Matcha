import SwiftUI

/// Settings > Advanced: web developer tools (`WebInspection`), like Safari's “Show features for web developers”.
struct AdvancedSettingsView: View {
    @AppStorage(BrowserSettings.Key.showsDeveloperTools) private var showsDeveloperTools = BrowserSettings.showsDeveloperTools

    var body: some View {
        Form {
            Section {
                Toggle("Show features for web developers", isOn: $showsDeveloperTools)
                    .accessibilityIdentifier("developerToolsToggle")
                    .onChange(of: showsDeveloperTools) {
                        NotificationCenter.default.post(name: WebInspection.didChange, object: nil)
                    }
            } footer: {
                Text(footer)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: LocalizedStringKey {
        WebInspection.offersInAppInspector
            ? """
            Adds Inspect Element to the menu of pages: the Web Inspector opens in Matcha. \
            Pages and extensions can also be inspected from the Develop menu of Safari.
            """
            : "Pages and extensions can be inspected from the Develop menu of Safari."
    }
}
