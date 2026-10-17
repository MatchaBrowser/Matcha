import SwiftUI

/// Ce que la fenêtre active expose aux commandes de menu.
extension FocusedValues {
    /// Onglets de la fenêtre active.
    @Entry var tabManager: TabManager?
    /// Actions de la fenêtre active (barre latérale, pastille d'adresse).
    @Entry var windowActions: WindowActions?
}
