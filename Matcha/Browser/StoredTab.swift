import Foundation

/// Ce qu'on enregistre d'un onglet (hors sa place dans la barre, décrite par `SidebarPosition`).
nonisolated struct StoredTab: Hashable, Sendable {
    var id: UUID
    var url: URL?
    var title: String?
    var pinnedURL: URL?
    var pinnedTitle: String?
    var lastActivity: Date
    /// État de navigation de WebKit (historique précédent/suivant, défilement), opaque.
    var interactionState: Data?
}
