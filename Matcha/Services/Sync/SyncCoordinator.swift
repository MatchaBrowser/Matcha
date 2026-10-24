import AppKit
import Foundation
import Observation
import OSLog
import SwiftData

/// Triggers sync (`SYNC.md` § 5): at startup, 2 seconds after a change on this Mac (synced records saved, synced
/// settings changed), when returning to the foreground, at regular intervals, on request (`syncSoon`, events of the
/// server), and when a waiting today tab page becomes stable. Only one sync at a time: a change made during a cycle
/// starts another one afterwards. History visits and unrelated settings trigger nothing. `stop` ends the running
/// cycle.
@MainActor
@Observable
final class SyncCoordinator {
    enum Status: Equatable {
        case idle
        case syncing
        /// Last cycle failed (`lastError`).
        case failed
    }

    private(set) var status = Status.idle
    private(set) var lastSyncDate: Date?
    /// Error of the last failed cycle.
    @ObservationIgnored private(set) var lastError: (any Error)?
    @ObservationIgnored let engine: SyncEngine
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored var interval: Duration
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var periodic: Task<Void, Never>?
    @ObservationIgnored private var cycle: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherCycle = false
    @ObservationIgnored private var watchedValues: NSDictionary?
    @ObservationIgnored private var watchedDefaults: UserDefaults?
    @ObservationIgnored private var watchedKeys: [String] = []
    /// Called after each cycle, successful or not (status shown in the settings, errors of the server).
    @ObservationIgnored var didFinishCycle: (@MainActor (_ error: (any Error)?) -> Void)?

    /// Models whose saves don't concern sync: a visit recorded in the history doesn't start a cycle.
    nonisolated static let unsyncedEntities: Set<String> = [Schema.entityName(for: HistoryRecord.self)]

    init(engine: SyncEngine, debounce: Duration = .seconds(2), interval: Duration = .seconds(15 * 60)) {
        self.engine = engine
        self.debounce = debounce
        self.interval = interval
    }

    /// Observes the saves of `context` and the `watchedKeys` of `defaults`, and starts a first cycle.
    func start(observing context: ModelContext, defaults: UserDefaults, watchedKeys: [String]) {
        stop()
        watchedDefaults = defaults
        self.watchedKeys = watchedKeys
        watchedValues = Self.values(of: watchedKeys, in: defaults)
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: ModelContext.didSave, object: context, queue: .main) { [weak self] notification in
                let concernsSync = Self.concernsSync(notification.userInfo)
                MainActor.assumeIsolated {
                    if concernsSync {
                        self?.localChange()
                    }
                }
            },
            center.addObserver(forName: UserDefaults.didChangeNotification, object: defaults, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.defaultsDidChange() }
            },
            center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.syncSoon(after: .zero) }
            },
        ]
        restartPeriodicSync()
        syncSoon(after: .zero)
    }

    /// No more triggers, and the running cycle is cancelled (its state is saved after each step).
    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        scheduled?.cancel()
        periodic?.cancel()
        cycle?.cancel()
        scheduled = nil
        periodic = nil
        cycle = nil
        needsAnotherCycle = false
    }

    /// A cycle every `interval` (15 minutes without the server's events), counted from now.
    func restartPeriodicSync() {
        periodic?.cancel()
        periodic = Task { [weak self, interval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else {
                    return
                }
                await self?.syncNow()
            }
        }
    }

    /// A watched setting changed (synced settings, zoom, extensions): a change of this Mac.
    private func defaultsDidChange() {
        guard let watchedDefaults else {
            return
        }
        let values = Self.values(of: watchedKeys, in: watchedDefaults)
        if values != watchedValues {
            watchedValues = values
            localChange()
        }
    }

    /// Change on this Mac: grouped with the ones that follow; during a cycle, another one follows it.
    private func localChange() {
        if engine.isSyncing {
            needsAnotherCycle = true
        } else {
            syncSoon(after: debounce)
        }
    }

    /// A cycle after `delay` (replaces the one already scheduled).
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

    /// A cycle right away (“Sync Now”); during a cycle, another one will follow.
    func syncNow() async {
        guard !engine.isSyncing, cycle == nil else {
            needsAnotherCycle = true
            return
        }
        let task = Task { await runCycle() }
        cycle = task
        await task.value
        cycle = nil
        if needsAnotherCycle {
            needsAnotherCycle = false
            syncSoon(after: debounce)
        } else if let next = engine.nextCheck {
            syncSoon(after: .seconds(max(next.timeIntervalSinceNow, 0.1)))
        }
    }

    private func runCycle() async {
        status = .syncing
        do {
            try await engine.sync()
            lastSyncDate = .now
            lastError = nil
            status = .idle
        } catch is CancellationError {
            status = .idle
            return
        } catch {
            Logger.sync.error("Sync failed: \(error.logSummary, privacy: .public)")
            lastError = error
            status = .failed
        }
        didFinishCycle?(lastError)
    }

    /// True if the save touched something else than the history.
    nonisolated static func concernsSync(_ userInfo: [AnyHashable: Any]?) -> Bool {
        let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
        let identifiers = keys.flatMap { userInfo?[$0.rawValue] as? [PersistentIdentifier] ?? [] }
        guard !identifiers.isEmpty else {
            // Nothing detailed: counted as a change.
            return true
        }
        return identifiers.contains { !unsyncedEntities.contains($0.entityName) }
    }

    private static func values(of keys: [String], in defaults: UserDefaults) -> NSDictionary {
        var values: [String: Any] = [:]
        for key in keys {
            values[key] = defaults.object(forKey: key)
        }
        return values as NSDictionary
    }
}
