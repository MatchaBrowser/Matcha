import Foundation
import OSLog

/// Moteur de synchro (tâche 7.4, `SYNC.md` § 2 et § 5), le même pour tous les transports. Un cycle relève les
/// changements de ce Mac, les envoie, lit ceux des autres et les applique, puis renvoie ce qui reste en attente. L'état
/// (`SyncState`) est enregistré après chaque étape : un cycle interrompu reprend où il en était.
@MainActor
final class SyncEngine {
    /// Choix de la première synchro quand ce Mac et les données synchronisées ont chacun leurs données (§ 5).
    enum FirstSyncChoice: Sendable {
        /// Union par identifiant ; ce qui est déjà synchronisé l'emporte.
        case merge
        /// Ce Mac prend les données synchronisées et retire les siennes.
        case replaceLocal
        /// Les données de ce Mac remplacent les données synchronisées.
        case replaceRemote
    }

    /// Bilan d'un cycle.
    struct Report: Equatable, Sendable {
        var sent = 0
        var received = 0
        var conflicts = 0
    }

    var state: SyncState
    let store: any SyncLocalStore
    let transport: any SyncTransport
    private let file: SyncStateFile
    var detector = SyncChangeDetector()
    /// Heure du Mac (remplacée dans les tests).
    var now: () -> Date = { .now }
    /// Choix de la première synchro quand il faut le demander ; fusionner par défaut.
    var chooseFirstSync: @MainActor () async -> FirstSyncChoice = { .merge }
    /// Date à laquelle relire ce Mac pour une page d'onglet du jour en attente ; nil s'il n'y en a pas.
    private(set) var nextCheck: Date?
    private(set) var isSyncing = false
    var report = Report()

    init(store: any SyncLocalStore, transport: any SyncTransport, file: SyncStateFile) {
        self.store = store
        self.transport = transport
        self.file = file
        state = file.load() ?? SyncState()
    }

    /// Un cycle ; nil si un cycle tourne déjà (une seule synchro à la fois).
    @discardableResult
    func sync() async throws -> Report? {
        guard !isSyncing else {
            return nil
        }
        isSyncing = true
        report = Report()
        defer { isSyncing = false }
        if state.hasCompletedFirstSync {
            detectLocalChanges()
            try await push()
            try await pull()
        } else {
            try await firstSync()
        }
        // Changements de ce Mac plus récents que ceux lus : repartent sur la version lue.
        try await push()
        save()
        let (sent, received, conflicts) = (report.sent, report.received, report.conflicts)
        Logger.sync.info(
            "Synchro : \(sent, privacy: .public) envoyés, \(received, privacy: .public) reçus, \(conflicts, privacy: .public) conflits",
        )
        return report
    }

    // MARK: Changements de ce Mac

    /// Relève les changements de ce Mac depuis sa dernière synchro et les met en attente d'envoi.
    func detectLocalChanges() {
        let (changes, next) = detector.changes(in: store.snapshot(), state: state, now: now())
        nextCheck = next
        changes.forEach(record)
    }

    private func record(_ change: SyncChangeDetector.Change) {
        let id = change.id
        state.rejected[id] = nil
        if let fields = change.fields {
            var content = SyncContent(fields: fields, modifiedAt: state.clock.next(now: now()), modifiedBy: state.deviceID)
            if let remote = state.entries[id]?.remote, !remote.deleted, remote.type == content.type {
                content.fields = content.fields.keepingUnknownKeys(of: remote.fields)
            }
            state.pending[id] = SyncPendingChange(content: content, local: fields.json)
        } else if state.entries[id]?.version == nil {
            // Jamais arrivé sur le serveur : rien à y supprimer.
            state.pending[id] = nil
            state.entries[id] = nil
        } else if let type = state.type(of: id) {
            let schema = SyncRecordType(rawValue: type)?.schema ?? 1
            let deletion = SyncContent.deletion(
                of: type,
                schema: schema,
                modifiedAt: state.clock.next(now: now()),
                modifiedBy: state.deviceID,
            )
            state.pending[id] = SyncPendingChange(content: deletion, local: nil)
        }
    }

    func save() {
        do {
            try file.save(state)
        } catch {
            Logger.sync.error("État de la synchro non enregistré : \(error.localizedDescription, privacy: .public)")
        }
    }
}
