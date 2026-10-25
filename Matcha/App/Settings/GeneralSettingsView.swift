import AppKit
import SwiftUI

/// General settings: default browser and links from other apps, homepage, new tabs, search and suggestions, link
/// peek, memory of inactive tabs, quitting the app, language.
struct GeneralSettingsView: View {
    @AppStorage(BrowserSettings.Key.homePage) private var homePage = BrowserSettings.homePage
    @AppStorage(BrowserSettings.Key.newTabPage) private var newTabPage = BrowserSettings.newTabPage
    @AppStorage(BrowserSettings.Key.searchEngine) private var searchEngine = BrowserSettings.searchEngine
    @AppStorage(BrowserSettings.Key.showsSearchSuggestions) private var showsSearchSuggestions = BrowserSettings.showsSearchSuggestions
    @AppStorage(BrowserSettings.Key.confirmBeforeQuitting) private var confirmBeforeQuitting = BrowserSettings.confirmBeforeQuitting
    @AppStorage(BrowserSettings.Key.opensPinnedLinksInPeek) private var opensPinnedLinksInPeek = BrowserSettings.opensPinnedLinksInPeek
    @AppStorage(BrowserSettings.Key.tabSuspensionDelay) private var tabSuspensionDelay = BrowserSettings.tabSuspensionDelay
    /// Homepage being typed: saved on Return, when the field loses focus or when Settings close, not at each keystroke,
    /// which recomputed every browser window (review IU1).
    @State private var homePageDraft: String?
    @FocusState private var isHomePageFocused: Bool

    var body: some View {
        Form {
            DefaultBrowserSection()
            Section {
                TextField("Homepage", text: homePageField, prompt: Text("e.g. apple.com"))
                    .focused($isHomePageFocused)
                    .onSubmit(saveHomePage)
                    .onChange(of: isHomePageFocused) { _, isFocused in
                        if !isFocused {
                            saveHomePage()
                        }
                    }
                    .onDisappear(perform: saveHomePage)
                    .accessibilityIdentifier("homePageField")
                Picker("New tabs open with", selection: $newTabPage) {
                    ForEach(NewTabPage.allCases) { page in
                        Text(page.title).tag(page)
                    }
                }
                .disabled((homePageDraft ?? homePage).trimmingCharacters(in: .whitespaces).isEmpty)
            }
            Section {
                Picker("Search engine", selection: $searchEngine) {
                    ForEach(SearchEngine.allCases, id: \.self) { engine in
                        Text(verbatim: engine.name).tag(engine)
                    }
                }
                .accessibilityIdentifier("searchEnginePicker")
                Toggle("Show search engine suggestions", isOn: $showsSearchSuggestions)
                    .accessibilityIdentifier("searchSuggestionsToggle")
            } footer: {
                Text("What you type in the command bar is sent to \(searchEngine.name) to suggest searches. Never in private windows.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Open links to other websites from Favorites and pinned tabs in Peek", isOn: $opensPinnedLinksInPeek)
                    .accessibilityIdentifier("pinnedLinksInPeekToggle")
            } footer: {
                Text("""
                Shift-click a link to open it in Peek without leaving the page. \
                With this option, Favorites and pinned tabs stay on their website.
                """, comment: "Settings > General: note under the Peek toggle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Picker("Free memory of inactive tabs after", selection: $tabSuspensionDelay) {
                    ForEach(TabSuspensionDelay.allCases) { delay in
                        Text(delay.title).tag(delay)
                    }
                }
                .accessibilityIdentifier("tabSuspensionDelayPicker")
            } footer: {
                Text("""
                Tabs you haven't looked at for this long free their memory, and sooner when your Mac runs low on memory. \
                They stay in the sidebar and reload when you show them; text typed in a page may be lost. \
                Tabs playing sound, using the camera or microphone, or allowed to send notifications are never affected.
                """, comment: "Settings > General: note under “Free memory of inactive tabs after”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Toggle("Ask before quitting", isOn: $confirmBeforeQuitting)
            }
            Section {
                LabeledContent("Language") {
                    Button("Change Language…", action: openLanguageSettings)
                        .accessibilityIdentifier("changeLanguageButton")
                }
            } footer: {
                Text("Matcha follows the language of macOS. To use another language in Matcha only, choose it in System Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // The window takes the height of its content: no scroll bar.
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// System Settings > General > Language & Region, where you choose the language of each app.
    private func openLanguageSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    /// The draft while typing, otherwise the saved homepage.
    private var homePageField: Binding<String> {
        Binding { homePageDraft ?? homePage } set: { homePageDraft = $0 }
    }

    private func saveHomePage() {
        if let homePageDraft, homePageDraft != homePage {
            homePage = homePageDraft
        }
        homePageDraft = nil
    }
}
