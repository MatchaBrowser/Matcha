import AppKit
import Foundation
import Observation
import OSLog
import SwiftData

/// Déclenche la synchro (tâche 7.4, `SYNC.md` § 5) : au démarrage, 2 secondes après un changement de ce Mac
/// (enregistrement de la base ou des réglages), au retour au premier plan, toutes les 15 minutes, et quand une page
/// d'onglet du jour en attente devient stable. Une seule synchro à la fois : une demande pendant un cycle en relance un
/// autre ensuite. Rien ne tourne avant `start` (synchro configurée, tâche 7.9).
@MainActor
@Observable
final class SyncCoordinator {
    enum Status: Equatable {
        case idle
        case syncing
        /// Dernier cycle en échec (message journalisé ; l'interface affichera le sien, tâche 7.9).
        case failed
    }

    private(set) var status = Status.idle
    private(set) var lastSyncDate: Date?
    @ObservationIgnored let engine: SyncEngine
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored private let interval: Duration
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var periodic: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherCycle = false

    init(engine: SyncEngine, debounce: Duration = .seconds(2), interval: Duration = .seconds(15 * 60)) {
        self.engine = engine
        self.debounce = debounce
        self.interval = interval
    }

    /// Suit les enregistrements de `context` et les réglages de `defaults`, et lance un premier cycle.
    func start(observing context: ModelContext, defaults: UserDefaults) {
        stop()
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: ModelContext.didSave, object: context, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.localChange() }
            },
            center.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.localChange() }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncSoon(after: .zero) }
            },
        ]
        periodic = Task { [weak self, interval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                await self?.syncNow()
            }
        }
        syncSoon(after: .zero)
    }

    /// Plus aucun déclencheur ; un cycle en cours se termine.
    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        scheduled?.cancel()
        periodic?.cancel()
        scheduled = nil
        periodic = nil
    }

    /// Changement de ce Mac : regroupé avec ceux qui suivent. Ceux qu'écrit la synchro elle-même sont ignorés.
    private func localChange() {
        guard !engine.isSyncing else {
            return
        }
        syncSoon(after: debounce)
    }

    /// Un cycle après `delay` (remplace celui déjà prévu).
    func syncSoon(after delay: Duration) {
        scheduled?.cancel()
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }
            await self?.syncNow()
        }
    }

    /// Un cycle tout de suite (« Synchroniser maintenant ») ; pendant un cycle, un autre suivra.
    func syncNow() async {
        guard !engine.isSyncing else {
            needsAnotherCycle = true
            return
        }
        status = .syncing
        do {
            try await engine.sync()
            lastSyncDate = .now
            status = .idle
        } catch {
            Logger.sync.error("Synchro en échec : \(error.localizedDescription, privacy: .public)")
            status = .failed
        }
        if needsAnotherCycle {
            needsAnotherCycle = false
            syncSoon(after: debounce)
        } else if let next = engine.nextCheck {
            syncSoon(after: .seconds(max(next.timeIntervalSinceNow, 0.1)))
        }
    }
}
