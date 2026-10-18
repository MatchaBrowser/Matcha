import SwiftUI

/// Message posé sur une page dont le processus s'est arrêté plusieurs fois de suite (tâche 5.7) : elle ne se recharge
/// plus d'elle-même. Le bouton, comme ⌘R, la recharge. Même style que l'accueil d'un onglet vide ; il couvre la page
/// (carte d'un panneau, aperçu, mini-fenêtre) et en prend les clics.
struct PageProblemView: View {
    let page: BrowserTab
    /// Rend la page active (panneau d'un split) quand on clique le message ou son bouton.
    var activate: () -> Void = {}

    var body: some View {
        ContentUnavailableView {
            Label {
                Text(
                    "This page had a problem",
                    comment: "Title of the message shown in place of a page whose content stopped working several times in a row",
                )
            } icon: {
                Image(systemName: "exclamationmark.triangle")
            }
        } description: {
            // Le site, sans l'adresse complète.
            Text(verbatim: AddressDisplay.short(for: page.url))
        } actions: {
            Button("Reload") { page.reload() }
                .accessibilityIdentifier("pageProblemReloadButton")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .contentShape(Rectangle())
        // Comme la barre d'adresse d'un panneau : un clic rend la page active, sans prendre le sien au bouton.
        .simultaneousGesture(TapGesture().onEnded { activate() })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pageProblem")
    }
}
