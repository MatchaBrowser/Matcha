import CryptoKit
import Foundation
@testable import Matcha
import Testing

/// Content of a synced record (task 7.4, `SYNC.md` § 2.2): JSON format, dates, conflict rule, identifiers derived from
/// a key, hybrid clock.
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
            Issue.record("Unreadable Space")
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

    @Test func `derived identifiers match the reference vectors`() throws {
        // `SYNC.md` § 3.10: account key = bytes 32 to 63.
        let identifiers = SyncIdentifiers(accountKey: SymmetricKey(data: Data(32 ..< 64)))
        let idKey = identifiers.idKey.withUnsafeBytes { Data($0) }
        #expect(idKey.map { String(format: "%02x", $0) }.joined() == "1566d83727cc0f51bd6130bcfbeb63b5edeed74d0aa752c98507d8610a539dac")
        let profile = try #require(UUID(uuidString: "9B1E4D2A-0C3F-4A6B-8E5D-7F2C1A9B3E40"))
        let vectors: [(UUID, String)] = [
            (identifiers.setting("searchEngine"), "29C6E709-25C1-837D-A81F-9938153247BB"),
            (identifiers.siteZoom("google.com"), "D841E19B-C45E-8758-A7F8-EE09968642E7"),
            (
                identifiers.sitePermission(profileID: profile, origin: "https://meet.google.com", kind: "camera"),
                "3574A498-BBBE-89DD-97E5-E8B259C7B0BF",
            ),
            (identifiers.packageExtension("0123456789abcdef0123456789abcdef"), "B146F347-53E0-8D14-B690-A7E7477085F7"),
            (identifiers.appExtension(bundleIdentifier: "com.example.DarkReader.Extension"), "B57FF5FB-0A29-8DBD-A38F-18FFB8646F9E"),
            (identifiers.defaultProfile, "F0C1AD76-39FD-8912-B97C-7D330800F8F3"),
            (identifiers.defaultSpace, "8467CEA7-A22F-842E-AF9E-B52B799680AE"),
        ]
        for (id, expected) in vectors {
            #expect(id == UUID(uuidString: expected))
        }
        // Another account gives other identifiers.
        #expect(SyncIdentifiers.testAccount.setting("searchEngine") != identifiers.setting("searchEngine"))
    }

    @Test func `a received record must carry the identifier its fields give`() {
        let identifiers = SyncIdentifiers.testAccount
        let zoom = SyncFields.siteZoom(SyncSiteZoomFields(site: "example.com", level: 1.5))
        #expect(identifiers.expectedID(of: zoom) == identifiers.siteZoom("example.com"))
        #expect(identifiers.expectedID(of: .profile(SyncProfileFields(name: "Perso", order: 0))) == nil)
    }

    @Test func `the clock never goes back`() throws {
        var clock = SyncClock()
        let now = try date("2026-10-17T08:30:12.345Z")
        #expect(clock.next(now: now) == now)
        // Same millisecond, then the Mac's clock running late: always 1 ms more.
        #expect(try clock.next(now: now) == date("2026-10-17T08:30:12.346Z"))
        #expect(try clock.next(now: now.addingTimeInterval(-60)) == date("2026-10-17T08:30:12.347Z"))
        // A change received from a Mac running ahead: the next one written here comes after it.
        try clock.observe(date("2026-10-17T09:00:00.000Z"))
        #expect(try clock.next(now: now) == date("2026-10-17T09:00:00.001Z"))
        // The Mac's time takes over again when it gets ahead.
        #expect(try clock.next(now: date("2026-10-17T10:00:00.000Z")) == date("2026-10-17T10:00:00.000Z"))
    }

    @Test func `a modification comes after the version it replaces, and the far future is not followed`() throws {
        var clock = SyncClock()
        let now = try date("2026-10-17T08:00:00.000Z")
        // The replaced content was written by a Mac running ahead: the modification comes 1 ms after it.
        #expect(try clock.next(now: now, after: date("2026-10-17T08:05:00.000Z")) == date("2026-10-17T08:05:00.001Z"))
        // A date more than 24 hours ahead of this Mac doesn't move the clock.
        #expect(try !clock.observe(date("2030-01-01T00:00:00.000Z"), now: now))
        #expect(try clock.next(now: now) == date("2026-10-17T08:05:00.002Z"))
        #expect(try clock.observe(date("2026-10-18T07:00:00.000Z"), now: now))
    }
}
