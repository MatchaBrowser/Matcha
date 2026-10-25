import SwiftUI

/// Appearance settings.
struct AppearanceSettingsView: View {
    @AppStorage(BrowserSettings.Key.appearance) private var appearance = BrowserSettings.appearance
    @AppStorage(BrowserSettings.Key.showsHomeButton) private var showsHomeButton = BrowserSettings.showsHomeButton
    @AppStorage(BrowserSettings.Key.homePage) private var homePage = BrowserSettings.homePage
    @AppStorage(BrowserSettings.Key.addressBarPosition) private var addressBarPosition = BrowserSettings.addressBarPosition
    @AppStorage(BrowserSettings.Key.showsNavigationButtons) private var showsNavigationButtons = BrowserSettings.showsNavigationButtons
    @AppStorage(BrowserSettings.Key.hiddenSidebarStyle) private var hiddenSidebarStyle = BrowserSettings.hiddenSidebarStyle

    var body: some View {
        Form {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Section {
                Picker("Address bar", selection: $addressBarPosition) {
                    ForEach(AddressBarPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
                Picker("When the sidebar is hidden", selection: $hiddenSidebarStyle) {
                    ForEach(HiddenSidebarStyle.allCases) { style in
                        Text(style.title).tag(style)
                    }
                }
                Toggle("Show Back, Forward, and Reload buttons", isOn: $showsNavigationButtons)
                Toggle(isOn: $showsHomeButton) {
                    Text("Show Home button")
                    if homePage.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("It only appears once you choose a homepage in the General tab.")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        // The appearance follows the setting in `MatchaApp` (scene `onChange`), even without a window (review CO4).
    }
}
