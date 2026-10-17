import Foundation

/// Zoom d'une page par ⌘+, ⌘-, ⌘0 et par la ligne « Zoom » des réglages du site (tâche 5.4) : `WKWebView.pageZoom`,
/// comme la propriété CSS `zoom` sur toute la page (le texte et la mise en page suivent, pas seulement l'image).
@MainActor
enum PageZoom {
    /// Vrai si `change` modifierait le zoom de `page` (menus grisés au bout de la liste ou déjà à 100 %).
    static func canApply(_ change: ZoomLevels.Change, to page: BrowserTab) -> Bool {
        page.isLoaded && change.level(from: page.pageZoom) != nil
    }

    /// Applique `change` à `page` ; avec `siteZooms`, le zoom est retenu pour son site et gagne ses autres pages
    /// ouvertes. Renvoie le nouveau zoom, ou nil si rien ne change.
    @discardableResult
    static func apply(_ change: ZoomLevels.Change, to page: BrowserTab, siteZooms: SiteZoomStore?) -> Double? {
        guard page.isLoaded, let level = change.level(from: page.pageZoom) else {
            return nil
        }
        if let siteZooms {
            siteZooms.setZoom(level, for: page)
        } else {
            page.setPageZoom(level)
        }
        return level
    }
}
