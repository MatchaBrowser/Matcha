/// Une fenêtre de navigation, vue par la mise en veille (tâche 5.6) : les onglets affichés par son Space affiché sont
/// visibles.
@MainActor
protocol TabDisplay: AnyObject {
    var displayedTabManager: TabManager { get }
}

extension WindowModel: TabDisplay {
    var displayedTabManager: TabManager {
        space.tabManager
    }
}
