import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Déclenchement de la synchro (tâche 7.4) : un premier cycle au démarrage, puis un cycle peu après chaque changement
/// enregistré de ce Mac.
@MainActor
struct SyncCoordinatorTests {
    private let server = InMemorySyncServer()

    /// Attend que `condition` devienne vraie (2 secondes au plus).
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
            store: MatchaSyncStore(session: session, defaults: defaults),
            transport: InMemorySyncTransport(server: server),
            file: SyncStateFile(url: nil),
        )
        let coordinator = SyncCoordinator(engine: engine, debounce: .milliseconds(50))
        defer { coordinator.stop() }
        coordinator.start(observing: session.container.mainContext, defaults: defaults)
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
        #expect(try await eventually { await server.content(of: SyncIdentifier.setting("searchEngine")) != nil })
        #expect(coordinator.status == .idle)
    }
}
