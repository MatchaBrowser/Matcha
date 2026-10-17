import Foundation

/// Aperçu d'un lien (tâche 4.4) : une page ouverte par-dessus les pages affichées, dans sa propre vue web, du
/// même profil. Hors de la barre latérale et jamais enregistré, jusqu'à « Ouvrir en onglet ».
struct Peek: Identifiable {
    /// Onglet hors rangement qui possède la vue web de l'aperçu ; il devient l'onglet ouvert.
    let tab: BrowserTab
    /// Onglet par-dessus lequel l'aperçu s'affiche ; en afficher un autre ferme l'aperçu.
    let sourceTabID: BrowserTab.ID
    /// Point d'où l'aperçu grandit, en fractions de la zone des pages (0…1, origine en haut à gauche).
    let openingPoint: CGPoint

    var id: BrowserTab.ID {
        tab.id
    }
}
