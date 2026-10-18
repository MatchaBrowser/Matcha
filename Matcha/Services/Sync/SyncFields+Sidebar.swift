import Foundation

/// Champs d'un profil (`SYNC.md` § 2.1).
nonisolated struct SyncProfileFields: Codable, Equatable, Sendable {
    var name: String
    var order: Int
}

/// Champs d'un Space : `symbol` comme `SpaceRecord.symbol`, `theme` comme `SpaceTheme` (nil : thème par défaut).
nonisolated struct SyncSpaceFields: Codable, Equatable, Sendable {
    var name: String
    var symbol: String
    var theme: SpaceTheme?
    var order: Int
    var profileId: UUID?
}

/// Champs d'un dossier d'épinglés : `icon` comme `FolderRecord.iconValue`, couleurs en « #RRGGBB ».
nonisolated struct SyncFolderFields: Codable, Equatable, Sendable {
    var name: String
    var order: Int
    var isCollapsed: Bool
    var spaceId: UUID?
    var parentId: UUID?
    var icon: String?
    var textColor: String?
    var backgroundColor: String?
}

/// Place d'un onglet synchronisé ; une autre valeur fait ignorer l'enregistrement.
nonisolated enum SyncTabPlace: String, Codable, Sendable {
    case favorite
    case pinned
    case today
}

/// Champs d'un onglet (`SYNC.md` § 2.1 et § 2.4) : adresse et titre d'origine d'un favori ou d'un épinglé, adresse et
/// titre courants d'un onglet du jour ; `profileId` pour un favori, `spaceId` pour les autres.
nonisolated struct SyncTabFields: Codable, Equatable, Sendable {
    var place: SyncTabPlace
    var url: URL?
    var title: String?
    var order: Int
    var profileId: UUID?
    var spaceId: UUID?
    var folderId: UUID?
    /// Dernière utilisation d'un onglet du jour ; nil pour les autres.
    var lastActivity: Date?

    /// Vrai si `other` ne diffère que par l'adresse, le titre ou la dernière utilisation d'un onglet du jour : un
    /// changement qui attend que la page soit stable avant de partir (`SYNC.md` § 2.4).
    func differsOnlyByPage(from other: SyncTabFields) -> Bool {
        guard place == .today, other.place == .today else {
            return false
        }
        var mine = self
        mine.url = other.url
        mine.title = other.title
        mine.lastActivity = other.lastActivity
        return mine == other
    }
}
