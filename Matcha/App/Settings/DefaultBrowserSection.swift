import AppKit
import SwiftUI

/// Réglages > Général, navigateur par défaut (tâches 8.2 et 8.3) : état et « Choisir par défaut… », puis où s'ouvrent
/// les liens cliqués dans d'autres apps.
struct DefaultBrowserSection: View {
    @AppStorage(BrowserSettings.Key.externalLinkDestination) private var destination = BrowserSettings.externalLinkDestination
    @State private var isDefault = DefaultBrowser.isMatcha
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
        // Changé ailleurs (Réglages Système, un autre navigateur) : relu au retour dans Matcha.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            isDefault = DefaultBrowser.isMatcha
        }
    }
}
