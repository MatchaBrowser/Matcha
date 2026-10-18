import Foundation

/// État de la synchro de ce Mac (tâche 7.4), conservé d'un lancement à l'autre : identifiant de l'appareil, curseur de
/// lecture, horloge, ce que le serveur a de chaque enregistrement et ce que ce Mac en avait alors, changements en
/// attente d'envoi. Type pur.
nonisolated struct SyncState: Codable, Equatable, Sendable {
    var deviceID = UUID()
    var cursor: String?
    var clock = SyncClock()
    var entries: [UUID: SyncEntry] = [:]
    var pending: [UUID: SyncPendingChange] = [:]
    /// Champs refusés par le serveur (trop gros…) : pas renvoyés tant qu'ils ne changent pas.
    var rejected: [UUID: SyncJSON] = [:]
    var hasCompletedFirstSync = false

    /// Ce que ce Mac avait de `id` à sa dernière synchro, ou ce qu'il s'apprête à envoyer ; nil : rien (absent).
    func baseline(of id: UUID) -> SyncJSON? {
        if let pending = pending[id] {
            return pending.local
        }
        return entries[id]?.local
    }

    /// Type connu de `id`.
    func type(of id: UUID) -> String? {
        pending[id]?.content.type ?? entries[id]?.type
    }
}

/// Un enregistrement connu de la synchro.
nonisolated struct SyncEntry: Codable, Equatable, Sendable {
    var type: String
    /// Version sur le serveur ; nil s'il n'y est pas encore.
    var version: Int?
    /// Dernier contenu connu du serveur.
    var remote: SyncContent?
    /// Champs de ce Mac à la dernière synchro de l'enregistrement ; nil s'il n'était pas sur ce Mac.
    var local: SyncJSON?
    /// Reçu mais pas encore appliqué : son parent manque.
    var isWaiting = false
}

/// Changement de ce Mac en attente d'envoi : le contenu, et les champs de ce Mac qu'il porte (nil : suppression).
nonisolated struct SyncPendingChange: Codable, Equatable, Sendable {
    var content: SyncContent
    var local: SyncJSON?
}

/// Fichier de l'état de la synchro (JSON) ; sans adresse (tests), rien n'est écrit.
nonisolated struct SyncStateFile: Sendable {
    let url: URL?

    func load() -> SyncState? {
        guard let url, let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? SyncCoding.decoder().decode(SyncState.self, from: data)
    }

    func save(_ state: SyncState) throws {
        guard let url else {
            return
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SyncCoding.encoder().encode(state).write(to: url, options: .atomic)
    }
}
