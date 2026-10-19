import AppKit
import Foundation
import Observation
import OSLog
import SwiftData

/// Triggers sync (task 7.4, `SYNC.md` § 5): at startup, 2 seconds after a change on this Mac (store or settings
/// saved), when returning to the foreground, every 15 minutes, and when a waiting today tab page becomes stable. Only
/// one sync at a time: a request during a cycle starts another one afterwards. Nothing runs before `start` (sync
/// configured, task 7.9).
@MainActor
@Observable
final class SyncCoordinator {
    enum Status: Equatable {
        case idle
        case syncing
        /// Last cycle failed (message logged; the interface will show its own, task 7.9).
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

    /// Observes the saves of `context` and the settings of `defaults`, and starts a first cycle.
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

    /// No more triggers; a cycle in progress finishes.
    func stop() {
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        scheduled?.cancel()
        periodic?.cancel()
        scheduled = nil
        periodic = nil
    }

    /// Change on this Mac: grouped with the ones that follow. Those written by sync itself are ignored.
    private func localChange() {
        guard !engine.isSyncing else {
            return
        }
        syncSoon(after: debounce)
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
            Logger.sync.error("Synchro en échec : \(error.logSummary, privacy: .public)")
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
