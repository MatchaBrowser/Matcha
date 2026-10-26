import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Sync triggering (task 7.4): a first cycle at startup, then a cycle shortly after each change saved on this Mac.
@MainActor
struct SyncCoordinatorTests {
    private let testDefaults = TestDefaults("SyncCoordinatorTests")
    private let server = InMemorySyncServer()

    @Test func `a change of this Mac leaves shortly after it is saved`() async throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let defaults = testDefaults.make()
        let engine = SyncEngine(
            store: MatchaSyncStore(session: session, defaults: defaults, identifiers: .testAccount),
            transport: InMemorySyncTransport(server: server),
            identifiers: .testAccount,
            file: SyncStateFile(url: nil),
        )
        let coordinator = SyncCoordinator(engine: engine, debounce: .milliseconds(50))
        defer { coordinator.stop() }
        coordinator.start(observing: session.container.mainContext, defaults: defaults, watchedKeys: SyncedSettings.keys)
        let space = try #require(session.spaces.first)
        try await waitUntilAsync { await server.content(of: space.id) != nil }
        #expect(coordinator.lastSyncDate != nil)

        session.renameSpace(space, to: "Renommé")
        try await waitUntilAsync {
            guard case let .space(fields) = await server.content(of: space.id)?.readableFields else {
                return false
            }
            return fields.name == "Renommé"
        }

        defaults.set("bing", forKey: BrowserSettings.Key.searchEngine)
        try await waitUntilAsync { await server.content(of: SyncIdentifiers.testAccount.setting("searchEngine")) != nil }
        // A cycle may still be running (the setting's own save triggers one): it ends idle.
        try await waitUntilAsync { coordinator.status == .idle }
    }

    /// A coordinator of an empty session, started, after its first cycle.
    private func startedCoordinator() async throws -> (SyncCoordinator, BrowserSession) {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let defaults = testDefaults.make()
        let engine = SyncEngine(
            store: MatchaSyncStore(session: session, defaults: defaults, identifiers: .testAccount),
            transport: InMemorySyncTransport(server: server),
            identifiers: .testAccount,
            file: SyncStateFile(url: nil),
        )
        let coordinator = SyncCoordinator(engine: engine, debounce: .milliseconds(50))
        coordinator.start(observing: session.container.mainContext, defaults: defaults, watchedKeys: SyncedSettings.keys)
        try await waitUntilAsync { coordinator.lastSyncDate != nil && coordinator.status == .idle }
        return (coordinator, session)
    }

    /// Review SY15: a save that changes nothing that travels (a today tab, its activity) starts no cycle.
    @Test func `a save with nothing to send starts no cycle`() async throws {
        let (coordinator, session) = try await startedCoordinator()
        defer { coordinator.stop() }
        let synced = coordinator.lastSyncDate
        let checks = coordinator.localChecks
        session.spaces[0].tabManager.newTab()
        session.saveAll()
        // The save is looked at, without the network (review TS2: a signal, not a fixed wait).
        try await waitUntil { coordinator.localChecks > checks }
        #expect(!coordinator.lastCheckFoundChanges)
        #expect(coordinator.lastSyncDate == synced)
    }

    /// Review SY34: the server's wait holds every trigger, “Sync Now” included.
    @Test func `the server's wait holds every trigger`() async throws {
        let (coordinator, _) = try await startedCoordinator()
        defer { coordinator.stop() }
        let synced = coordinator.lastSyncDate
        coordinator.wait(until: .now.addingTimeInterval(0.5))
        await coordinator.syncNow()
        #expect(coordinator.lastSyncDate == synced)
        try await waitUntilAsync { coordinator.lastSyncDate != synced }
    }

    /// Review TS8: a failed cycle is reported, and a later one ends idle.
    @Test func `a failed cycle is reported and the next one recovers`() async throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let defaults = testDefaults.make()
        let engine = SyncEngine(
            store: MatchaSyncStore(session: session, defaults: defaults, identifiers: .testAccount),
            transport: LossyTransport(server: server, losses: LossyTransport.Losses(1)),
            identifiers: .testAccount,
            file: SyncStateFile(url: nil),
        )
        let coordinator = SyncCoordinator(engine: engine, debounce: .milliseconds(50))
        defer { coordinator.stop() }
        var outcomes: [String] = []
        coordinator.didFinishCycle = { error in
            outcomes.append(error.map { $0 is URLError ? "network" : "other" } ?? "done")
        }
        coordinator.start(observing: session.container.mainContext, defaults: defaults, watchedKeys: SyncedSettings.keys)
        try await waitUntil { !outcomes.isEmpty }
        #expect(outcomes == ["network"])
        #expect(coordinator.status == .failed)
        #expect(coordinator.lastSyncDate == nil)

        await coordinator.syncNow()
        try await waitUntil { coordinator.status == .idle && outcomes.last == "done" }
        #expect(coordinator.lastSyncDate != nil)
    }

    /// A model saved, under the key of the notification that names it.
    enum Saved: Sendable {
        case insertedVisit, updatedVisit, deletedVisit, updatedTab, deletedTab

        var key: ModelContext.NotificationKey {
            switch self {
            case .insertedVisit: .insertedIdentifiers
            case .updatedVisit, .updatedTab: .updatedIdentifiers
            case .deletedVisit, .deletedTab: .deletedIdentifiers
            }
        }

        var isTab: Bool {
            self == .updatedTab || self == .deletedTab
        }
    }

    /// Review SY17: only a save that touches something else than the history starts a cycle.
    @Test(arguments: [
        ([], false),
        ([.insertedVisit], false),
        ([.insertedVisit, .updatedVisit, .deletedVisit], false),
        ([.updatedTab], true),
        ([.insertedVisit, .deletedTab], true),
    ] as [([Saved], Bool)])
    func `only saves beyond the history concern sync`(saved: [Saved], concernsSync: Bool) throws {
        let container = try BrowserSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        let visit = HistoryRecord(
            url: testURL("https://example.test/"),
            urlKey: "example.test",
            title: nil,
            visitDate: .now,
            profileID: nil,
            spaceID: nil,
        )
        let tab = TabRecord(url: testURL("https://example.test/"))
        context.insert(visit)
        context.insert(tab)
        try context.save()
        var userInfo: [AnyHashable: Any] = [:]
        for model in saved {
            let identifiers = userInfo[model.key.rawValue] as? [PersistentIdentifier] ?? []
            userInfo[model.key.rawValue] = identifiers + [model.isTab ? tab.persistentModelID : visit.persistentModelID]
        }
        #expect(SyncCoordinator.concernsSync(userInfo) == concernsSync)
        #expect(!SyncCoordinator.concernsSync(nil))
    }
}
