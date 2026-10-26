import Foundation
@testable import Matcha
import Testing

/// Cost of a sync cycle (review SY13): the JSON of an unchanged record is reused, and an unchanged state is not
/// written again.
@MainActor
struct SyncJSONCacheTests {
    private let server = InMemorySyncServer()

    @Test func `the cache gives each record's JSON, encoded again only where it changed`() {
        var cache = SyncJSONCache()
        let one = UUID()
        let two = UUID()
        var snapshot: [UUID: SyncFields] = [
            one: .profile(SyncProfileFields(name: "Perso", order: 0)),
            two: .profile(SyncProfileFields(name: "Travail", order: 1)),
        ]
        #expect(cache.encoded(snapshot) == snapshot.mapValues(\.encodedJSON))
        snapshot[one] = .profile(SyncProfileFields(name: "Renommé", order: 0))
        snapshot[two] = nil
        let encoded = cache.encoded(snapshot)
        #expect(encoded == snapshot.mapValues(\.encodedJSON))
        #expect(encoded[two] == nil)
        // Fields that can't be encoded stay nil, as without the cache (review SY28).
        snapshot[two] = .profile(SyncProfileFields(name: "Infini", order: .infinity))
        #expect(cache.encoded(snapshot)[two] == .some(nil))
    }

    @Test func `a cycle that changes nothing doesn't write the state again`() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "SyncJSONCacheTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let file = folder.appending(path: "state.json")
        let mac = SimulatedMac(server: server)
        let engine = SyncEngine(
            store: mac.store,
            transport: InMemorySyncTransport(server: server),
            identifiers: .testAccount,
            file: SyncStateFile(url: file),
        )
        engine.now = { mac.time }
        let space = mac.addSpace("Perso", profile: mac.addProfile("Personnel"))
        try await engine.sync()
        // The next cycle reads back what this one sent (versions, cursor): the state changes once more.
        mac.time += 1
        try await engine.sync()

        // An old date, that only a new write changes.
        let old = Date(timeIntervalSince1970: 1_000_000_000)
        try FileManager.default.setAttributes([.modificationDate: old], ofItemAtPath: file.path)
        mac.time += 1
        try await engine.sync()
        #expect(try modificationDate(of: file) == old)

        mac.rename(space, to: "Renommé")
        mac.time += 1
        try await engine.sync()
        #expect(try modificationDate(of: file) > old)
    }

    private func modificationDate(of file: URL) throws -> Date {
        try #require(try FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate] as? Date)
    }
}
