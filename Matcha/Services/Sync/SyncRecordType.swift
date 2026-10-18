import Foundation

/// Type d'un enregistrement synchronisé (tâche 7.4, `SYNC.md` § 2.1), dans l'ordre d'application d'un lot reçu
/// (§ 2.3) : profils, Spaces, dossiers, onglets, extensions, réglages, décisions de site. Type pur.
nonisolated enum SyncRecordType: String, CaseIterable, Codable, Sendable {
    case profile
    case space
    case folder
    case tab
    case webExtension = "extension"
    case setting
    case sitePermission
    case siteZoom

    /// Version du format des champs de ce type, écrite dans chaque contenu (`schema`).
    var schema: Int {
        1
    }

    /// Rang dans l'ordre d'application : un parent passe avant ce qu'il contient.
    var applyRank: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }
}
