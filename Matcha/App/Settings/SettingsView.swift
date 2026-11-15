import SwiftUI

/// Settings window (⌘,). The tab shown follows `SettingsSelection` (“Manage Extensions…” opens Extensions).
struct SettingsView: View {
    /// Wide enough for the names of all the tabs in the toolbar, in each language (`SettingsToolbarTests`): the
    /// longest, German, needs 710 points on macOS 26.
    static let width: CGFloat = 720

    /// The app's (`AppEnvironment`).
    @Bindable var selection: SettingsSelection
    let extensions: ExtensionManager
    let extensionSync: ExtensionSyncAdapter
    let menuShortcuts: MenuShortcutStore
    let shortcutRecorder: ShortcutRecorder
    let vault: VaultService

    var body: some View {
        TabView(selection: $selection.tab) {
            GeneralSettingsView()
                .settingsTab(.general)
            ShortcutsSettingsView(store: menuShortcuts, recorder: shortcutRecorder)
                .settingsTab(.shortcuts)
            AppearanceSettingsView()
                .settingsTab(.appearance)
            ProfilesSettingsView()
                .settingsTab(.profiles)
            PrivacySettingsView()
                .settingsTab(.privacy)
            ExtensionsSettingsView(manager: extensions, syncAdapter: extensionSync)
                .settingsTab(.extensions)
            SyncSettingsView()
                .settingsTab(.sync)
            VaultSettingsView(vault: vault)
                .settingsTab(.vault)
            AdvancedSettingsView()
                .settingsTab(.advanced)
        }
        .frame(width: Self.width)
    }
}

private extension View {
    func settingsTab(_ tab: SettingsSelection.Tab) -> some View {
        tabItem { Label { Text(tab.title) } icon: { Image(systemName: tab.symbol) } }
            .tag(tab)
    }
}
