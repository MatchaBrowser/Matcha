import Foundation
@testable import Matcha
import Testing

/// Contenu d'un enregistrement synchronisé (tâche 7.4, `SYNC.md` § 2.2) : format JSON, dates, règle des conflits,
/// identifiants tirés d'une clé, horloge hybride.
struct SyncContentTests {
    private let device = UUID(uuidString: "3F2A8C1E-6B0D-4C5E-9F1A-2B7D8E4C6A10") ?? UUID()

    private func date(_ text: String) throws -> Date {
        try #require(SyncCoding.date(from: text))
    }

    @Test func `the example of the spec is read and written back`() throws {
        let json = """
        {"deleted":false,"fields":{"name":"Perso","order":0,"profileId":"9B1E4D2A-0C3F-4A6B-8E5D-7F2C1A9B3E40","symbol":"house.fill",\
        "theme":{"angle":135,"colors":[{"blue":0.33,"green":0.7,"red":0.55},{"blue":0.1,"green":0.21,"red":0.14}],"name":"matcha"}},\
        "modifiedAt":"2026-10-17T08:30:12.345Z","modifiedBy":"3F2A8C1E-6B0D-4C5E-9F1A-2B7D8E4C6A10","schema":1,"type":"space"}
        """
        let content = try SyncContent.decoded(from: Data(json.utf8))
        #expect(content.recordType == .space)
        #expect(try content.modifiedAt == date("2026-10-17T08:30:12.345Z"))
        guard case let .space(fields) = content.readableFields else {
            Issue.record("Space illisible")
            return
        }
        #expect(fields.name == "Perso")
        #expect(fields.theme?.colors.first == ThemeColor(red: 0.55, green: 0.7, blue: 0.33))
        #expect(fields.profileId == UUID(uuidString: "9B1E4D2A-0C3F-4A6B-8E5D-7F2C1A9B3E40"))
        #expect(try String(bytes: content.encoded(), encoding: .utf8) == json)
    }

    @Test func `dates keep the millisecond`() throws {
        #expect(SyncCoding.string(from: Date(timeIntervalSince1970: 0)) == "1970-01-01T00:00:00.000Z")
        let date = try date("2026-10-17T08:30:12.345Z")
        #expect(SyncCoding.string(from: date) == "2026-10-17T08:30:12.345Z")
        #expect(SyncCoding.string(from: date.addingTimeInterval(0.0004)) == "2026-10-17T08:30:12.345Z")
        #expect(try self.date("2026-10-17T08:30:12Z") == date.addingTimeInterval(-0.345))
        #expect(try self.date("2026-10-17T08:30:12.3456Z") == date)
        #expect(SyncCoding.date(from: "hier") == nil)
    }

    @Test func `a deletion has no fields`() throws {
        let deletion = SyncContent.deletion(of: "tab", schema: 1, modifiedAt: .now, modifiedBy: device)
        #expect(deletion.fields == .emptyObject)
        #expect(deletion.readableFields == nil)
        let decoded = try SyncContent.decoded(from: deletion.encoded())
        #expect(decoded == deletion)
    }

    @Test func `the latest modification wins, then the largest device`() throws {
        let earlier = try date("2026-10-17T08:30:12.345Z")
        let small = try #require(UUID(uuidString: "0A000000-0000-0000-0000-000000000000"))
        let large = try #require(UUID(uuidString: "B0000000-0000-0000-0000-000000000000"))
        let first = SyncContent.deletion(of: "tab", schema: 1, modifiedAt: earlier, modifiedBy: large)
        let second = SyncContent.deletion(of: "tab", schema: 1, modifiedAt: earlier.addingTimeInterval(0.001), modifiedBy: small)
        #expect(second.isNewer(than: first))
        #expect(!first.isNewer(than: second))
        let tie = SyncContent.deletion(of: "tab", schema: 1, modifiedAt: earlier, modifiedBy: small)
        #expect(first.isNewer(than: tie))
        #expect(!tie.isNewer(than: first))
        #expect(!first.isNewer(than: first))
    }

    @Test func `content from a newer version is kept as is`() {
        let newer = SyncContent(type: "space", schema: 2, modifiedAt: .now, modifiedBy: device, deleted: false, fields: .emptyObject)
        #expect(newer.isFromNewerVersion)
        #expect(newer.readableFields == nil)
        let unknown = SyncContent(type: "boost", schema: 1, modifiedAt: .now, modifiedBy: device, deleted: false, fields: .emptyObject)
        #expect(unknown.recordType == nil)
        #expect(unknown.isFromNewerVersion)
    }

    @Test func `derived identifiers are UUID version 5`() throws {
        // RFC 9562, annexe A.4 : « www.example.com » dans l'espace de noms DNS.
        let dns = try #require(UUID(uuidString: "6BA7B810-9DAD-11D1-80B4-00C04FD430C8"))
        #expect(SyncIdentifier.derived(from: "www.example.com", in: dns) == UUID(uuidString: "2ED6657D-E927-568B-95E1-2665A8AEA6A2"))
        #expect(SyncIdentifier.namespace == UUID(uuidString: "393070D0-1478-44F6-82BF-07476B17D5F5"))
        #expect(SyncIdentifier.setting("searchEngine") == SyncIdentifier.derived(from: "setting:searchEngine"))
        #expect(SyncIdentifier.setting("searchEngine") != SyncIdentifier.setting("appearance"))
        let profile = try #require(UUID(uuidString: "9B1E4D2A-0C3F-4A6B-8E5D-7F2C1A9B3E40"))
        #expect(
            SyncIdentifier.sitePermission(profileID: profile, origin: "https://meet.google.com", kind: "camera")
                == SyncIdentifier.derived(from: "site-permission:9b1e4d2a-0c3f-4a6b-8e5d-7f2c1a9b3e40|https://meet.google.com|camera"),
        )
        #expect(SyncIdentifier.webExtension("dark-reader") == SyncIdentifier.derived(from: "extension:dark-reader"))
        #expect(SyncIdentifier.siteZoom("example.com") == SyncIdentifier.derived(from: "site-zoom:example.com"))
    }

    @Test func `the clock never goes back`() throws {
        var clock = SyncClock()
        let now = try date("2026-10-17T08:30:12.345Z")
        #expect(clock.next(now: now) == now)
        // Même milliseconde, puis horloge du Mac en retard : toujours 1 ms de plus.
        #expect(try clock.next(now: now) == date("2026-10-17T08:30:12.346Z"))
        #expect(try clock.next(now: now.addingTimeInterval(-60)) == date("2026-10-17T08:30:12.347Z"))
        // Une modification reçue d'un Mac en avance : la suivante écrite ici vient après elle.
        try clock.observe(date("2026-10-17T09:00:00.000Z"))
        #expect(try clock.next(now: now) == date("2026-10-17T09:00:00.001Z"))
        // L'heure du Mac reprend la main quand elle dépasse.
        #expect(try clock.next(now: date("2026-10-17T10:00:00.000Z")) == date("2026-10-17T10:00:00.000Z"))
    }
}
