import OSLog
import SwiftUI
import WebKit

/// Privacy settings: clear cookies and site data, permission decisions remembered per site, ad and tracker blocker
/// (setting, lists, exceptions, credits; task 6.2, hidden while it is set aside).
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
            SiteActionsSection(store: session.sitePermissions.actions, profiles: session.profiles)
            // Blocker (task 6.2): the app's, with the saved exceptions.
            if ContentBlockerService.isAvailable {
                let contentBlocker = session.contentBlocking.service
                ContentBlockerSettingsSection(service: contentBlocker)
                ContentBlockerExceptionsSection(service: contentBlocker)
                BlocklistCreditsSection(service: contentBlocker)
            }
        }
        .formStyle(.grouped)
        // The window takes the height of its content: no scroll bar.
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
        // All profiles: each one has its own data store.
        for store in session.allDataStores() {
            await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        }
        Logger.app.info("Cookies and website data cleared")
        isClearing = false
        lastCleared = .now
    }
}
