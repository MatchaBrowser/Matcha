import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Sync triggering (task 7.4): a first cycle at startup, then a cycle shortly after each change saved on this Mac.
@MainActor
struct SyncCoordinatorTests {
    private let server = InMemorySyncServer()

    /// Waits until `condition` becomes true (2 seconds at most).
    private func eventually(_ condition: () async -> Bool) async throws -> Bool {
        for _ in 0 ..< 100 {
            if await condition() {
                return true
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        return await condition()
    }

    @Test func `a change of this Mac leaves shortly after it is saved`() async throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let defaults = try #require(UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)"))
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
        #expect(try await eventually { await server.content(of: space.id) != nil })
        #expect(coordinator.lastSyncDate != nil)

        session.renameSpace(space, to: "Renommé")
        #expect(try await eventually {
            guard case let .space(fields) = await server.content(of: space.id)?.readableFields else {
                return false
            }
            return fields.name == "Renommé"
        })

        defaults.set("bing", forKey: BrowserSettings.Key.searchEngine)
        #expect(try await eventually { await server.content(of: SyncIdentifiers.testAccount.setting("searchEngine")) != nil })
        // A cycle may still be running (the setting's own save triggers one): it ends idle.
        #expect(try await eventually { coordinator.status == .idle })
    }

    /// A coordinator of an empty session, started, after its first cycle.
    private func startedCoordinator() async throws -> (SyncCoordinator, BrowserSession) {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let defaults = try #require(UserDefaults(suiteName: "SyncCoordinatorTests-\(UUID().uuidString)"))
        let engine = SyncEngine(
            store: MatchaSyncStore(session: session, defaults: defaults, identifiers: .testAccount),
            transport: InMemorySyncTransport(server: server),
            identifiers: .testAccount,
            file: SyncStateFile(url: nil),
        )
        let coordinator = SyncCoordinator(engine: engine, debounce: .milliseconds(50))
        coordinator.start(observing: session.container.mainContext, defaults: defaults, watchedKeys: SyncedSettings.keys)
        #expect(try await eventually { coordinator.lastSyncDate != nil && coordinator.status == .idle })
        return (coordinator, session)
    }

    /// Review SY15: a save that changes nothing that travels (a today tab, its activity) starts no cycle.
    @Test func `a save with nothing to send starts no cycle`() async throws {
        let (coordinator, session) = try await startedCoordinator()
        defer { coordinator.stop() }
        let synced = coordinator.lastSyncDate
        session.spaces[0].tabManager.newTab()
        session.saveAll()
        try await Task.sleep(for: .milliseconds(400))
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
        #expect(try await eventually { coordinator.lastSyncDate != synced })
    }
}
