import OSLog
import SwiftUI
import WebKit

/// Privacy settings: clear cookies and site data, what a local page received from another app may read (review WB11),
/// permission decisions remembered per site, ad and tracker blocker (setting, lists, exceptions, credits; task 6.2,
/// hidden while it is set aside).
struct PrivacySettingsView: View {
    @Environment(BrowserSession.self) private var session
    @AppStorage(BrowserSettings.Key.filesFromOtherAppsReadFolder)
    private var filesFromOtherAppsReadFolder = BrowserSettings.filesFromOtherAppsReadFolder
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
                // WebKit offers no public way to forget the passwords of login sheets (review WB17): they stay for the session.
                Text("""
                Cookies, local storage, caches, and other website data for all profiles. You will be signed out; \
                a password typed in a login sheet is kept until you quit Matcha.
                """, comment: "Settings > Privacy: what “Clear…” removes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle(isOn: $filesFromOtherAppsReadFolder) {
                    Text(
                        "Files opened from other apps can read their folder",
                        comment: "Settings > Privacy: a local page opened from the Finder or another app may read the files next to it",
                    )
                }
                .accessibilityIdentifier("filesFromOtherAppsReadFolderToggle")
            } footer: {
                Text("""
                A web page opened from the Finder or another app then shows the images next to it, and can read the \
                other files of its folder. Off, it reads only itself; File > Open File… (⌘O) shows its images.
                """, comment: "Settings > Privacy: explanation of the setting of the local pages opened from other apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            SitePermissionsSection(store: session.sitePermissions, profiles: session.profiles)
            SiteActionsSection(store: session.sitePermissions.actions, profiles: session.profiles)
            // Blocker (task 6.2): the app's, with the saved exceptions.
            if let contentBlocker = session.contentBlocking?.service {
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
            Text("""
            You will be signed out of all websites; a password typed in a login sheet is kept until you quit Matcha. \
            This action cannot be undone.
            """, comment: "Settings > Privacy: confirmation message before clearing the data of all websites")
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
