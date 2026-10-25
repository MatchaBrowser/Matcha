import AppKit
import Foundation
import Observation
import OSLog
import SwiftData

/// Triggers sync (`SYNC.md` § 5): at startup, when returning to the foreground (at most once a minute), at regular
/// intervals, on request (`syncSoon`, events of the server), and for a change on this Mac (synced records saved, synced
/// settings changed): 2 seconds later, this Mac is read without the network, and a cycle starts only if there is
/// something to send (review SY15), never for a save of sync itself, nor a tab clicked. Only one sync at a time: a
/// change made during a cycle is looked at afterwards. History visits and unrelated settings trigger nothing. A wait
/// asked by the server (`Retry-After`) holds every trigger (`wait(until:)`, review SY34). `stop` ends the running
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
    @ObservationIgnored let engine: SyncEngine
    @ObservationIgnored private let debounce: Duration
    @ObservationIgnored var interval: Duration
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var scheduled: Task<Void, Never>?
    @ObservationIgnored private var periodic: Task<Void, Never>?
    @ObservationIgnored private var cycle: Task<Void, Never>?
    @ObservationIgnored private var scheduledCheck: Task<Void, Never>?
    @ObservationIgnored private var needsAnotherCycle = false
    @ObservationIgnored private var needsLocalCheck = false
    /// No cycle before this date: the server asked to wait.
    @ObservationIgnored private(set) var notBefore: Date?
    /// Returning to the foreground syncs at most this often.
    static let foregroundInterval: TimeInterval = 60
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
                MainActor.assumeIsolated { self?.didBecomeActive() }
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
        scheduledCheck?.cancel()
        periodic?.cancel()
        cycle?.cancel()
        scheduled = nil
        scheduledCheck = nil
        periodic = nil
        cycle = nil
        needsAnotherCycle = false
        needsLocalCheck = false
    }

    /// The server asked to wait until `date` (`Retry-After`): every trigger waits, then a cycle runs.
    func wait(until date: Date) {
        notBefore = max(notBefore ?? date, date)
        syncSoon(after: .zero)
    }

    private func didBecomeActive() {
        if lastSyncDate.map({ Date.now.timeIntervalSince($0) >= Self.foregroundInterval }) ?? true {
            syncSoon(after: .zero)
        }
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

    /// Change on this Mac: grouped with the ones that follow, then looked at; during a cycle (its own saves included),
    /// looked at afterwards.
    private func localChange() {
        if engine.isSyncing || cycle != nil {
            needsLocalCheck = true
        } else {
            checkLocalChanges(after: debounce)
        }
    }

    /// After `delay`, a cycle if this Mac has something to send (read without the network).
    private func checkLocalChanges(after delay: Duration) {
        scheduledCheck?.cancel()
        scheduledCheck = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else {
                return
            }
            self?.checkLocalChangesNow()
        }
    }

    private func checkLocalChangesNow() {
        guard !engine.isSyncing, cycle == nil else {
            needsLocalCheck = true
            return
        }
        do {
            let (hasChanges, next) = try engine.localChangesToSend()
            if hasChanges {
                syncSoon(after: .zero)
            } else if let next {
                checkLocalChanges(after: .seconds(max(next.timeIntervalSinceNow, 0.1)))
            }
        } catch {
            // This Mac couldn't be read: the cycle reports it.
            syncSoon(after: .zero)
        }
    }

    /// A cycle after `delay` (replaces the one already scheduled), never before the server's wait.
    func syncSoon(after delay: Duration) {
        scheduled?.cancel()
        let wait = notBefore.map { Duration.seconds(max($0.timeIntervalSinceNow, 0)) } ?? .zero
        scheduled = Task { [weak self] in
            try? await Task.sleep(for: max(delay, wait))
            guard !Task.isCancelled else {
                return
            }
            await self?.syncNow()
        }
    }

    /// A cycle right away (“Sync Now”); during a cycle, another one will follow. During the server's wait, the cycle
    /// is put off until it ends.
    func syncNow() async {
        if let notBefore, notBefore > .now {
            syncSoon(after: .zero)
            return
        }
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
        } else if needsLocalCheck {
            needsLocalCheck = false
            checkLocalChanges(after: debounce)
        } else if let next = engine.nextCheck {
            checkLocalChanges(after: .seconds(max(next.timeIntervalSinceNow, 0.1)))
        }
    }

    private func runCycle() async {
        status = .syncing
        let error: (any Error)?
        do {
            try await engine.sync()
            lastSyncDate = .now
            status = .idle
            error = nil
        } catch let failure {
            // Stopped (signed out, account changed): not a failure, whatever the error the network gave (review SY7).
            guard !Task.isCancelled, !(failure is CancellationError), (failure as? URLError)?.code != .cancelled else {
                status = .idle
                return
            }
            if let server = failure as? SyncServerError {
                Logger.sync.error("Sync failed: \(server.code, privacy: .public) (\(server.status, privacy: .public))")
            } else {
                Logger.sync.error("Sync failed: \(failure.logSummary, privacy: .public)")
            }
            status = .failed
            error = failure
        }
        didFinishCycle?(error)
    }

    /// True if the save touched something else than the history.
    nonisolated static func concernsSync(_ userInfo: [AnyHashable: Any]?) -> Bool {
        let keys: [ModelContext.NotificationKey] = [.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
        let identifiers = keys.flatMap { userInfo?[$0.rawValue] as? [PersistentIdentifier] ?? [] }
        guard !identifiers.isEmpty else {
            // A save that changed nothing (review SY17).
            return false
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
