import AppKit
import KeyboardShortcuts
import SwiftUI

/// Réglages généraux : navigateur par défaut et liens d'autres apps, page d'accueil, nouveaux onglets, recherche et
/// suggestions, aperçu des liens, mémoire des onglets inactifs, raccourci de la mini-fenêtre, fermeture de l'app, langue.
struct GeneralSettingsView: View {
    @AppStorage(BrowserSettings.Key.homePage) private var homePage = BrowserSettings.homePage
    @AppStorage(BrowserSettings.Key.newTabPage) private var newTabPage = BrowserSettings.newTabPage
    @AppStorage(BrowserSettings.Key.searchEngine) private var searchEngine = BrowserSettings.searchEngine
    @AppStorage(BrowserSettings.Key.showsSearchSuggestions) private var showsSearchSuggestions = BrowserSettings.showsSearchSuggestions
    @AppStorage(BrowserSettings.Key.confirmBeforeQuitting) private var confirmBeforeQuitting = BrowserSettings.confirmBeforeQuitting
    @AppStorage(BrowserSettings.Key.opensPinnedLinksInPeek) private var opensPinnedLinksInPeek = BrowserSettings.opensPinnedLinksInPeek
    @AppStorage(BrowserSettings.Key.tabSuspensionDelay) private var tabSuspensionDelay = BrowserSettings.tabSuspensionDelay

    var body: some View {
        Form {
            DefaultBrowserSection()
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
                Tabs playing sound or using the camera or microphone are never affected.
                """, comment: "Settings > General: note under “Free memory of inactive tabs after”")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Mini Window Shortcut") {
                    // Ses propres textes (effacer, raccourci refusé) sont traduits par KeyboardShortcuts.
                    KeyboardShortcuts.Recorder(for: .openMiniWindow)
                        .accessibilityIdentifier("miniWindowShortcutRecorder")
                }
            } footer: {
                Text("""
                Press this shortcut in any app to open a mini window, even when Matcha is in the background. \
                It uses the profile of the Space shown.
                """, comment: "Settings > General: note under the mini window shortcut")
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
