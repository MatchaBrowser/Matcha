import Foundation

/// Champs d'un enregistrement synchronisé, par type (tâche 7.4, `SYNC.md` § 2.1) : ce que ce Mac a, ou ce qu'il a lu
/// d'un contenu reçu. Un champ absent vaut `null`. Type pur.
nonisolated enum SyncFields: Equatable, Sendable {
    case profile(SyncProfileFields)
    case space(SyncSpaceFields)
    case folder(SyncFolderFields)
    case tab(SyncTabFields)
    case webExtension(SyncExtensionFields)
    case setting(SyncSettingFields)
    case sitePermission(SyncSitePermissionFields)
    case siteZoom(SyncSiteZoomFields)

    var type: SyncRecordType {
        switch self {
        case .profile: .profile
        case .space: .space
        case .folder: .folder
        case .tab: .tab
        case .webExtension: .webExtension
        case .setting: .setting
        case .sitePermission: .sitePermission
        case .siteZoom: .siteZoom
        }
    }

    /// Champs en JSON (objet).
    var json: SyncJSON {
        let value: SyncJSON? = switch self {
        case let .profile(fields): try? .encoding(fields)
        case let .space(fields): try? .encoding(fields)
        case let .folder(fields): try? .encoding(fields)
        case let .tab(fields): try? .encoding(fields)
        case let .webExtension(fields): try? .encoding(fields)
        case let .setting(fields): try? .encoding(fields)
        case let .sitePermission(fields): try? .encoding(fields)
        case let .siteZoom(fields): try? .encoding(fields)
        }
        return value ?? .emptyObject
    }

    /// Champs de type `type` lus dans `json` ; nil si une valeur manque ou sort des valeurs connues (place, réglage,
    /// permission, zoom…). Les champs inconnus sont ignorés.
    init?(json: SyncJSON, type: SyncRecordType) {
        let fields: SyncFields? = switch type {
        case .profile: (try? json.decoded(as: SyncProfileFields.self)).map(SyncFields.profile)
        case .space: (try? json.decoded(as: SyncSpaceFields.self)).map(SyncFields.space)
        case .folder: (try? json.decoded(as: SyncFolderFields.self)).map(SyncFields.folder)
        case .tab: (try? json.decoded(as: SyncTabFields.self)).map(SyncFields.tab)
        case .webExtension: (try? json.decoded(as: SyncExtensionFields.self)).map(SyncFields.webExtension)
        case .setting: (try? json.decoded(as: SyncSettingFields.self)).flatMap { $0.isValid ? .setting($0) : nil }
        case .sitePermission: (try? json.decoded(as: SyncSitePermissionFields.self)).flatMap { $0.isValid ? .sitePermission($0) : nil }
        case .siteZoom: (try? json.decoded(as: SyncSiteZoomFields.self)).flatMap { $0.isValid ? .siteZoom($0) : nil }
        }
        guard let fields else {
            return nil
        }
        self = fields
    }

    /// Parent dont l'enregistrement a besoin (profil, Space, dossier), s'il en a un.
    var parentIDs: [UUID] {
        switch self {
        case .profile, .webExtension, .setting, .siteZoom: []
        case let .space(fields): fields.profileId.map { [$0] } ?? []
        case let .folder(fields): [fields.spaceId, fields.parentId].compactMap(\.self)
        case let .tab(fields): [fields.profileId, fields.spaceId, fields.folderId].compactMap(\.self)
        case let .sitePermission(fields): fields.profileId.map { [$0] } ?? []
        }
    }
}
