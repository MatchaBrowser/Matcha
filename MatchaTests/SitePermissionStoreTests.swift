import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Décisions retenues (tâche 5.2) : table en mémoire, enregistrement SwiftData, fenêtres privées, profils supprimés.
@MainActor
struct SitePermissionStoreTests {
    private let meet = TestOrigins.meet
    private let profile = UUID()

    // MARK: Table

    @Test func `decisions are kept per profile and origin`() throws {
        var table = SitePermissionTable()
        table.set(.allow, for: .camera, origin: meet, profileID: profile)
        table.set(.deny, for: .microphone, origin: meet, profileID: profile)

        #expect(table.decisions(for: meet, profileID: profile) == [.camera: .allow, .microphone: .deny])
        #expect(table.decisions(for: meet, profileID: UUID()).isEmpty)
        #expect(table.decisions(for: TestOrigins.other, profileID: profile).isEmpty)
        // Même hôte, autre schéma ou autre port : une autre origine.
        #expect(try table.decisions(for: #require(SiteOrigin(scheme: "http", host: meet.host, port: nil)), profileID: profile).isEmpty)

        table.set(nil, for: .camera, origin: meet, profileID: profile)
        #expect(table.decisions(for: meet, profileID: profile) == [.microphone: .deny])
    }

    @Test func `the most recent of duplicate decisions wins`() {
        let key = SitePermissionEntry.Key(profileID: profile, origin: meet, kind: .camera)
        let old = SitePermissionEntry(key: key, decision: .deny, date: .distantPast)
        let recent = SitePermissionEntry(key: key, decision: .allow, date: .now)
        #expect(SitePermissionTable([recent, old]).decisions(for: meet, profileID: profile)[.camera] == .allow)
        #expect(SitePermissionTable([old, recent]).decisions(for: meet, profileID: profile)[.camera] == .allow)
    }

    @Test func `entries are sorted by site then permission`() {
        var table = SitePermissionTable()
        table.set(.deny, for: .microphone, origin: TestOrigins.other, profileID: profile)
        table.set(.allow, for: .microphone, origin: meet, profileID: profile)
        table.set(.allow, for: .camera, origin: meet, profileID: profile)
        table.set(.allow, for: .camera, origin: TestOrigins.local, profileID: profile)

        let order = table.sortedEntries.map { "\($0.origin.displayHost) \($0.kind.rawValue)" }
        #expect(order == [
            "localhost:8080 camera",
            "meet.example.com camera",
            "meet.example.com microphone",
            "other.example.org microphone",
        ])
    }

    @Test func `removing a profile forgets only its decisions`() {
        let other = UUID()
        var table = SitePermissionTable()
        table.set(.allow, for: .camera, origin: meet, profileID: profile)
        table.set(.deny, for: .camera, origin: meet, profileID: other)
        table.removeAll(profileID: profile)
        #expect(table.decisions(for: meet, profileID: profile).isEmpty)
        #expect(table.decisions(for: meet, profileID: other) == [.camera: .deny])
    }

    // MARK: Enregistrement

    @Test func `decisions are saved and read back`() throws {
        let container = try BrowserSchema.makeContainer(inMemory: true)
        let store = SitePermissionStore(context: container.mainContext)
        #expect(store.isPersistent)
        store.set(.allow, for: .camera, origin: meet, profileID: profile)
        store.set(.deny, for: .microphone, origin: TestOrigins.local, profileID: profile)

        let records = try container.mainContext.fetch(FetchDescriptor<SitePermissionRecord>(sortBy: [SortDescriptor(\.originKey)]))
        #expect(records.map(\.originKey) == ["http://localhost:8080", "https://meet.example.com"])
        #expect(records.map(\.kindValue) == ["microphone", "camera"])
        #expect(records.map(\.decisionValue) == ["deny", "allow"])
        #expect(records.allSatisfy { $0.profileID == profile })

        let reopened = SitePermissionStore(context: container.mainContext)
        #expect(reopened.decisions(for: meet, profileID: profile) == [.camera: .allow])
        #expect(reopened.decision(.microphone, for: TestOrigins.local, profileID: profile) == .deny)
        #expect(reopened.entries.count == 2)
    }

    @Test func `changing a decision updates its record, ask deletes it`() throws {
        let container = try BrowserSchema.makeContainer(inMemory: true)
        let store = SitePermissionStore(context: container.mainContext)
        store.set(.allow, for: .camera, origin: meet, profileID: profile)
        store.set(.deny, for: .camera, origin: meet, profileID: profile)

        let records = try container.mainContext.fetch(FetchDescriptor<SitePermissionRecord>())
        #expect(records.count == 1)
        #expect(records.first?.decisionValue == "deny")

        store.set(nil, for: .camera, origin: meet, profileID: profile)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<SitePermissionRecord>()) == 0)
        #expect(store.entries.isEmpty)
    }

    @Test func `unreadable records are ignored`() throws {
        let container = try BrowserSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        let broken = SitePermissionRecord(profileID: profile, originKey: "pas une origine", kind: .camera, decision: .allow)
        let unknown = SitePermissionRecord(profileID: profile, originKey: meet.key, kind: .camera, decision: .allow)
        unknown.kindValue = "geolocation"
        context.insert(broken)
        context.insert(unknown)
        try context.save()
        #expect(SitePermissionStore(context: context).entries.isEmpty)
    }

    @Test func `a private window keeps its decisions in memory only`() throws {
        let session = BrowserSession.makePrivate()
        let store = session.sitePermissions
        #expect(!store.isPersistent)
        store.set(.allow, for: .camera, origin: meet, profileID: nil)

        #expect(store.decision(.camera, for: meet, profileID: nil) == .allow)
        #expect(try session.container.mainContext.fetchCount(FetchDescriptor<SitePermissionRecord>()) == 0)
        // Une autre fenêtre privée, ou la session normale, ne la voit pas.
        #expect(BrowserSession.makePrivate().sitePermissions.entries.isEmpty)
        let regular = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        #expect(regular.sitePermissions.isPersistent)
        #expect(regular.sitePermissions.entries.isEmpty)
    }

    @Test func `deleting a profile deletes its decisions`() async throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        session.addProfile(named: "Travail")
        let kept = try #require(session.profiles.first?.id)
        let deleted = try #require(session.profiles.last)
        session.sitePermissions.set(.allow, for: .camera, origin: meet, profileID: kept)
        session.sitePermissions.set(.deny, for: .camera, origin: meet, profileID: deleted.id)

        await session.deleteProfile(deleted)

        #expect(session.sitePermissions.entries.map(\.profileID) == [kept])
        let records = try session.container.mainContext.fetch(FetchDescriptor<SitePermissionRecord>())
        #expect(records.map(\.profileID) == [kept])
    }

    /// Les Spaces donnent à leurs onglets les décisions de leur profil.
    @Test func `spaces see the decisions of their profile`() throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let work = session.addProfile(named: "Travail")
        let first = try #require(session.spaces.first)
        let firstScope = try #require(first.tabManager.sitePermissions)
        let workScope = try #require(work.tabManager.sitePermissions)
        #expect(firstScope.store === session.sitePermissions)
        #expect(firstScope.profileID == first.record.profile?.id)
        #expect(workScope.profileID == work.record.profile?.id)

        firstScope.set(.allow, for: .camera, origin: meet)
        #expect(firstScope.decision(.camera, for: meet) == .allow)
        #expect(workScope.decision(.camera, for: meet) == nil)
    }
}
