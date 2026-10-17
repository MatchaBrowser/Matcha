import AppKit
import SwiftUI

/// Réglages généraux : page d'accueil, nouveaux onglets, recherche et suggestions, aperçu des liens, fermeture de
/// l'app, langue.
struct GeneralSettingsView: View {
    @AppStorage(BrowserSettings.Key.homePage) private var homePage = BrowserSettings.homePage
    @AppStorage(BrowserSettings.Key.newTabPage) private var newTabPage = BrowserSettings.newTabPage
    @AppStorage(BrowserSettings.Key.searchEngine) private var searchEngine = BrowserSettings.searchEngine
    @AppStorage(BrowserSettings.Key.showsSearchSuggestions) private var showsSearchSuggestions = BrowserSettings.showsSearchSuggestions
    @AppStorage(BrowserSettings.Key.confirmBeforeQuitting) private var confirmBeforeQuitting = BrowserSettings.confirmBeforeQuitting
    @AppStorage(BrowserSettings.Key.opensPinnedLinksInPeek) private var opensPinnedLinksInPeek = BrowserSettings.opensPinnedLinksInPeek

    var body: some View {
        Form {
            Section {
                TextField("Homepage", text: $homePage, prompt: Text("e.g. apple.com"))
                    .accessibilityIdentifier("homePageField")
                Picker("New tabs open with", selection: $newTabPage) {
                    ForEach(NewTabPage.allCases) { page in
                        Text(page.title).tag(page)
                    }
                }
                .disabled(homePage.trimmingCharacters(in: .whitespaces).isEmpty)
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
        // La fenêtre prend la hauteur du contenu : pas de barre de défilement.
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// Réglages Système > Général > Langue et région, où l'on choisit la langue de chaque app.
    private func openLanguageSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
