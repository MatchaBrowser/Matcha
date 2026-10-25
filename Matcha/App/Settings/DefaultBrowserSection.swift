import AppKit
import SwiftUI

/// Settings > General, default browser (tasks 8.2 and 8.3): status and “Make Default…”, then where links clicked in
/// other apps open.
struct DefaultBrowserSection: View {
    @AppStorage(BrowserSettings.Key.externalLinkDestination) private var destination = BrowserSettings.externalLinkDestination
    /// Read when the section appears, not at each `init` (LaunchServices, review IU8).
    @State private var isDefault = false
    @State private var isAsking = false

    var body: some View {
        Section {
            LabeledContent("Default Browser") {
                if isDefault {
                    Text("Matcha is your default browser.")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("defaultBrowserStatus")
                } else {
                    Button("Make Default…") {
                        isAsking = true
                        Task {
                            isDefault = await DefaultBrowser.makeMatcha()
                            isAsking = false
                        }
                    }
                    .disabled(isAsking)
                    .help("macOS asks you to confirm")
                    .accessibilityIdentifier("makeDefaultBrowserButton")
                }
            }
            Picker("Open links from other apps in", selection: $destination) {
                ForEach(ExternalLinkDestination.allCases) { destination in
                    Text(destination.title).tag(destination)
                }
            }
            .accessibilityIdentifier("externalLinkDestinationPicker")
        } footer: {
            Text("Links you click in Mail, Messages or other apps open in Matcha when it is your default browser.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .onAppear { isDefault = DefaultBrowser.isMatcha }
        // Changed elsewhere (System Settings, another browser): read again on returning to Matcha.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isDefault = DefaultBrowser.isMatcha
        }
    }
}
