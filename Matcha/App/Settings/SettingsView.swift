import SwiftUI

/// Fenêtre des réglages (⌘,). L'onglet affiché suit `SettingsSelection` (« Gérer les extensions… » ouvre Extensions).
struct SettingsView: View {
    @Bindable private var selection = SettingsSelection.shared

    var body: some View {
        TabView(selection: $selection.tab) {
            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsSelection.Tab.general)
            AppearanceSettingsView()
                .tabItem { Label("Appearance", systemImage: "paintbrush") }
                .tag(SettingsSelection.Tab.appearance)
            ProfilesSettingsView()
                .tabItem { Label("Profiles", systemImage: "person.2") }
                .tag(SettingsSelection.Tab.profiles)
            PrivacySettingsView()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
                .tag(SettingsSelection.Tab.privacy)
            ExtensionsSettingsView()
                .tabItem { Label("Extensions", systemImage: "puzzlepiece.extension") }
                .tag(SettingsSelection.Tab.extensions)
            AdvancedSettingsView()
                .tabItem { Label("Advanced", systemImage: "gearshape.2") }
                .tag(SettingsSelection.Tab.advanced)
        }
        .frame(width: 520)
    }
}
