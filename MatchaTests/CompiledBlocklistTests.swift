import Foundation
@testable import Matcha
import Testing

/// Saved compiled lists (task 6.2): store identifiers (version included, parts), version to reuse, stale
/// identifiers (never those of another prefix), saving in the settings.
struct CompiledBlocklistTests {
    private let entry = BlocklistEntry(identifier: "easylist", name: "EasyList", version: "2026.10.18", file: "a.json")

    private func record(version: String = "2026.10.18", parts: Int = 1) -> CompiledBlocklist {
        let entry = BlocklistEntry(identifier: "easylist", name: "EasyList", version: version, file: "a.json")
        return CompiledBlocklist(
            identifier: "easylist",
            version: version,
            storeIdentifiers: CompiledBlocklist.storeIdentifiers(for: entry, partCount: parts),
            ruleCount: 12,
            compiledAt: Date(timeIntervalSince1970: 1_000_000),
        )
    }

    @Test func `store identifiers carry the list and its version`() {
        #expect(CompiledBlocklist.storeIdentifiers(for: entry, partCount: 1) == ["matcha-blocklist.easylist.2026.10.18"])
        #expect(CompiledBlocklist.storeIdentifiers(for: entry, partCount: 3) == [
            "matcha-blocklist.easylist.2026.10.18.part-1",
            "matcha-blocklist.easylist.2026.10.18.part-2",
            "matcha-blocklist.easylist.2026.10.18.part-3",
        ])
    }

    @Test func `the same version is reused, another one is not`() {
        #expect(record().matches(entry))
        #expect(record(parts: 2).matches(entry))
        #expect(!record(version: "2026.10.11").matches(entry))
        let other = BlocklistEntry(identifier: "easyprivacy", name: "EasyPrivacy", version: "2026.10.18", file: "b.json")
        #expect(!record().matches(other))
    }

    @Test func `a record with foreign or no store identifiers is not reused`() {
        let foreign = CompiledBlocklist(
            identifier: "easylist",
            version: "2026.10.18",
            storeIdentifiers: ["autre.easylist"],
            ruleCount: 1,
            compiledAt: .now,
        )
        let empty = CompiledBlocklist(identifier: "easylist", version: "2026.10.18", storeIdentifiers: [], ruleCount: 1, compiledAt: .now)
        #expect(!foreign.matches(entry))
        #expect(!empty.matches(entry))
    }

    @Test func `only our unused identifiers are stale`() {
        let available = [
            "matcha-blocklist.easylist.2026.10.18",
            "matcha-blocklist.easylist.2026.10.11",
            "matcha-blocklist.retiree.1.part-2",
            "extension.ublock",
            "autre",
        ]
        let stale = CompiledBlocklist.staleIdentifiers(available: available, keeping: ["matcha-blocklist.easylist.2026.10.18"])
        #expect(stale == ["matcha-blocklist.easylist.2026.10.11", "matcha-blocklist.retiree.1.part-2"])
    }

    @Test func `records are saved in the settings and read back`() throws {
        let suiteName = "CompiledBlocklistTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        #expect(CompiledBlocklist.load(from: defaults).isEmpty)
        let records = [record(), record(version: "3", parts: 2)]
        CompiledBlocklist.save(records, to: defaults)
        #expect(CompiledBlocklist.load(from: defaults) == records)
        CompiledBlocklist.save([], to: defaults)
        #expect(defaults.object(forKey: CompiledBlocklist.defaultsKey) == nil)
        defaults.set(Data("illisible".utf8), forKey: CompiledBlocklist.defaultsKey)
        #expect(CompiledBlocklist.load(from: defaults).isEmpty)
        #expect(CompiledBlocklist.load(from: nil).isEmpty)
    }
}
