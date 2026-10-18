import Foundation

/// Transport de la synchro (tâche 7.4) : ce qui change entre un serveur (7.7) et iCloud (reporté). Il envoie des lots,
/// lit les changements depuis un curseur, et chiffre ou déchiffre les contenus (`SYNC.md` § 3.5) : le moteur ne voit que
/// des contenus en clair.
protocol SyncTransport: Sendable {
    /// Nombre de changements par envoi (`maxChangesPerPush`).
    var maxChangesPerPush: Int { get }

    /// Envoie `changes`, dans l'ordre ; un résultat par changement, dans le même ordre.
    func push(_ changes: [SyncOutgoingChange]) async throws -> [SyncPushResult]

    /// Changements écrits après `cursor` (nil : depuis le début), par version croissante. Lance
    /// `SyncTransportError.cursorExpired` si le curseur est trop ancien.
    func changes(since cursor: String?) async throws -> SyncChangePage

    /// Vrai si le transport garde les paquets d'extension (`SYNC.md` § 4.7) ; sinon, une extension installée depuis un
    /// fichier voyage sans son paquet.
    var supportsBlobs: Bool { get }

    /// Envoie un paquet déjà chiffré ; sans effet si le même existe déjà sous cet identifiant.
    func putBlob(_ data: Data, id: UUID) async throws

    /// Paquet chiffré `id` ; lance `SyncTransportError.blobNotFound` s'il n'est pas (encore) là.
    func blob(id: UUID) async throws -> Data

    /// Supprime le paquet `id` (sans erreur s'il n'existe pas).
    func deleteBlob(id: UUID) async throws
}

/// Changement envoyé : `baseVersion` est la version sur laquelle il repose, nil pour une création.
nonisolated struct SyncOutgoingChange: Equatable, Sendable {
    let id: UUID
    let baseVersion: Int?
    let content: SyncContent
}

/// Enregistrement lu sur le serveur. `content` est nil s'il n'a pas pu être déchiffré ou lu : il est alors ignoré, et
/// jamais écrasé.
nonisolated struct SyncRemoteRecord: Equatable, Sendable {
    let id: UUID
    let version: Int
    let content: SyncContent?
}

/// Sort d'un changement envoyé (`SYNC.md` § 4.6).
nonisolated enum SyncPushResult: Equatable, Sendable {
    case applied(version: Int)
    /// `baseVersion` n'était plus la version du serveur : rien n'est écrit, voici l'enregistrement actuel.
    case conflict(current: SyncRemoteRecord)
    case rejected(code: String)
}

/// Une page de changements lus.
nonisolated struct SyncChangePage: Equatable, Sendable {
    let records: [SyncRemoteRecord]
    let cursor: String
    let hasMore: Bool
}

nonisolated enum SyncTransportError: Error, Equatable {
    /// Curseur trop ancien (`410 cursor_expired`) : tout relire depuis le début.
    case cursorExpired
    /// Paquet absent (`404`) : il arrivera peut-être plus tard.
    case blobNotFound
    /// Un autre paquet porte déjà cet identifiant (`409 blob_exists`).
    case blobExists
}
