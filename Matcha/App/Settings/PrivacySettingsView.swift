import OSLog
import SwiftUI
import WebKit

/// Réglages de confidentialité : effacer cookies et données des sites, décisions de permission retenues par site.
struct PrivacySettingsView: View {
    @Environment(BrowserSession.self) private var session
    @State private var isConfirmingClear = false
    @State private var isClearing = false
    @State private var lastCleared: Date?

    var body: some View {
        Form {
            Section {
                LabeledContent("Cookies and website data") {
                    Button("Clear…") { isConfirmingClear = true }
                        .disabled(isClearing)
                }
                if let lastCleared {
                    Text("Data cleared at \(lastCleared.formatted(date: .omitted, time: .shortened)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Cookies, local storage, caches, and other website data for all profiles. You will be signed out.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SitePermissionsSection(store: session.sitePermissions, profiles: session.profiles)
        }
        .formStyle(.grouped)
        // La fenêtre prend la hauteur du contenu : pas de barre de défilement.
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Clear cookies and data for all websites?", isPresented: $isConfirmingClear) {
            Button("Clear", role: .destructive) {
                Task { await clearWebsiteData() }
            }
        } message: {
            Text("You will be signed out of all websites. This action cannot be undone.")
        }
    }

    private func clearWebsiteData() async {
        isClearing = true
        // Tous les profils : chacun a son propre magasin de données.
        for store in session.allDataStores() {
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        }
        Logger.app.info("Cookies et données des sites effacés")
        isClearing = false
        lastCleared = .now
    }
}
