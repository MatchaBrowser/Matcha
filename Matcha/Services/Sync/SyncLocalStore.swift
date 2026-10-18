import Foundation

/// Données de ce Mac vues par le moteur de synchro (tâche 7.4) : leur état actuel, enregistrement par enregistrement, et
/// l'application de ce qui est reçu. Implémenté pour Matcha par `MatchaSyncStore`, et en mémoire dans les tests.
@MainActor
protocol SyncLocalStore: AnyObject {
    /// État actuel de chaque enregistrement synchronisé de ce Mac.
    func snapshot() -> [UUID: SyncFields]

    /// Applique `changes`, dans l'ordre donné (parents d'abord) ; renvoie les enregistrements mis en attente faute de
    /// leur parent (`SYNC.md` § 2.3 : masqués jusqu'à la lecture suivante).
    func apply(_ changes: [SyncLocalChange]) -> Set<UUID>

    /// Vrai si ce Mac n'a que les données de son premier lancement (`SYNC.md` § 5) : à la première synchro, il prend
    /// alors les données synchronisées et retire les siennes.
    var hasOnlyFirstLaunchData: Bool { get }
}

/// Changement reçu, à appliquer sur ce Mac.
nonisolated enum SyncLocalChange: Equatable, Sendable {
    case upsert(UUID, SyncFields)
    case delete(UUID, SyncRecordType)

    var id: UUID {
        switch self {
        case let .upsert(id, _), let .delete(id, _): id
        }
    }

    /// Ordre d'application d'un lot : créations et modifications des parents d'abord (profils, Spaces, dossiers,
    /// onglets…), puis les suppressions, du contenu vers les parents.
    static func ordered(_ changes: [SyncLocalChange]) -> [SyncLocalChange] {
        changes.sorted { first, second in
            switch (first, second) {
            case let (.upsert(_, firstFields), .upsert(_, secondFields)): firstFields.type.applyRank < secondFields.type.applyRank
            case (.upsert, .delete): true
            case (.delete, .upsert): false
            case let (.delete(_, firstType), .delete(_, secondType)): firstType.applyRank > secondType.applyRank
            }
        }
    }
}
