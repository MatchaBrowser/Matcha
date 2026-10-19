import SwiftUI

/// Settings window (⌘,). The tab shown follows `SettingsSelection` (“Manage Extensions…” opens Extensions).
struct SettingsView: View {
    /// The app's (`AppEnvironment`).
    @Bindable var selection: SettingsSelection
    let extensions: ExtensionManager
    let extensionSync: ExtensionSyncAdapter
    let menuShortcuts: MenuShortcutStore
    let shortcutRecorder: ShortcutRecorder

    var body: some View {
        TabView(selection: $selection.tab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsSelection.Tab.general)
            ShortcutsSettingsView(store: menuShortcuts, recorder: shortcutRecorder)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsSelection.Tab.shortcuts)
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(SettingsSelection.Tab.appearance)
            ProfilesSettingsView()
                .tabItem { Label("Profiles", systemImage: "person.2") }
                .tag(SettingsSelection.Tab.profiles)
            PrivacySettingsView()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .tag(SettingsSelection.Tab.privacy)
            ExtensionsSettingsView(manager: extensions, syncAdapter: extensionSync)
                .tabItem { Label("Extensions", systemImage: "puzzlepiece.extension") }
                .tag(SettingsSelection.Tab.extensions)
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
                .tag(SettingsSelection.Tab.advanced)
        }
        .frame(width: 520)
    }
}
