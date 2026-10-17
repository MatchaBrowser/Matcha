import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Horloge réglable des tests de l'historique.
@MainActor
final class TestClock {
    var now: Date

    init(_ now: Date = fixedNow) {
        self.now = now
    }

    func advance(_ seconds: TimeInterval) {
        now = now.addingTimeInterval(seconds)
    }
}

/// Magasin de l'historique (tâche 5.5) : écriture, lecture hors du fil principal, profils, suppressions, durée de
/// conservation.
@MainActor
struct HistoryStoreTests {
    private let container: ModelContainer
    private let clock = TestClock()
    private let store: HistoryStore
    private let profile = UUID()
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }()

    init() throws {
        container = try BrowserSchema.makeContainer(inMemory: true)
        store = HistoryStore(container: container, now: { [clock] in clock.now }, calendar: calendar)
    }

    private func makeStore() -> HistoryStore {
        HistoryStore(container: container, now: { [clock] in clock.now }, calendar: calendar)
    }

    @discardableResult
    private func record(_ address: String, title: String? = nil, profileID: UUID? = nil, in store: HistoryStore? = nil) -> HistoryVisit {
        (store ?? self.store).recordVisit(url: URL(string: address)!, title: title, profileID: profileID ?? profile, spaceID: nil)
    }

    private func entries(_ text: String, profileID: UUID? = nil, in store: HistoryStore? = nil) async -> [HistoryEntry] {
        await (store ?? self.store).entries(profileID: profileID ?? profile, matching: query(text), limit: 300)
    }

    private var recordCount: Int {
        (try? container.mainContext.fetchCount(FetchDescriptor<HistoryRecord>())) ?? -1
    }

    @Test func `visits are written and read back`() async throws {
        record("https://example.com/", title: "Exemple")
        clock.advance(120)
        await store.load()
        #expect(store.isLoaded)
        let revision = store.revision
        record("https://www.example.com/", title: "Exemple 2")
        #expect(store.revision == revision + 1)

        let found = await entries("exem")
        #expect(found.count == 1)
        #expect(found.first?.visitCount == 2)
        #expect(found.first?.title == "Exemple 2")
        #expect(recordCount == 2)
        let saved = try container.mainContext.fetch(FetchDescriptor<HistoryRecord>(sortBy: [SortDescriptor(\.visitDate)]))
        #expect(saved.map(\.urlKey) == ["example.com", "example.com"])
        #expect(saved.allSatisfy { $0.profileID == profile && $0.spaceID == nil })
    }

    @Test func `each profile only sees its own history`() async {
        let other = UUID()
        record("https://travail.example/", title: "Travail", profileID: other)
        record("https://perso.example/", title: "Perso")
        #expect(await entries("example").map(\.title) == ["Perso"])
        #expect(await entries("example", profileID: other).map(\.title) == ["Travail"])
        #expect(await entries("example", profileID: UUID()).isEmpty)
        #expect(store.index(for: other)?.entries.count == 1)
    }

    @Test func `visits written while the history loads count once`() async {
        for round in 0 ..< 5 {
            let store = makeStore()
            record("https://avant.example/\(round)", in: store)
            let loading = Task { await store.load() }
            await Task.yield()
            record("https://pendant.example/\(round)", title: "Pendant", in: store)
            await loading.value
            let index = store.index(for: profile)
            #expect(index?.entries["pendant.example/\(round)"]?.visitCount == 1)
            #expect(index?.entries["avant.example/\(round)"]?.visitCount == 1)
        }
    }

    @Test func `refreshed visits and late titles are saved`() async throws {
        let visit = record("https://example.com/")
        clock.advance(10)
        #expect(store.refreshVisit(visit.id, title: nil, profileID: profile))
        store.setTitle("Titre tardif", ofVisit: visit.id, profileID: profile)
        #expect(!store.refreshVisit(UUID(), title: nil, profileID: profile))

        // Relu par un autre magasin : la date et le titre ont été enregistrés.
        let reopened = makeStore()
        await reopened.load()
        let entry = try #require(reopened.index(for: profile)?.entries["example.com"])
        #expect(entry.title == "Titre tardif")
        #expect(entry.visitCount == 1)
        #expect(entry.lastVisit == fixedNow.addingTimeInterval(10))
    }

    @Test func `visits older than one year are erased when the history is read`() async throws {
        let context = container.mainContext
        let old = try #require(calendar.date(byAdding: .day, value: -366, to: fixedNow))
        try context.insert(HistoryRecord(
            url: #require(URL(string: "https://ancien.example/")), urlKey: "ancien.example", title: "Ancien", visitDate: old,
            profileID: profile, spaceID: nil,
        ))
        try context.save()
        record("https://recent.example/", title: "Récent")
        await store.load()
        #expect(store.index(for: profile)?.entries.keys.sorted() == ["recent.example"])
        #expect(recordCount == 1)
    }

    @Test func `deleting rows removes their visits only`() async {
        let first = record("https://example.com/", title: "Exemple")
        clock.advance(3600)
        record("https://example.com/", title: "Exemple")
        let other = record("https://apple.com/", title: "Apple")
        await store.load()

        store.deleteVisits([first.id, other.id], profileID: profile)
        #expect(store.index(for: profile)?.entries.keys.sorted() == ["example.com"])
        #expect(store.index(for: profile)?.entries["example.com"]?.visitCount == 1)
        #expect(recordCount == 1)
        store.deleteVisits([], profileID: profile)
        #expect(recordCount == 1)
    }

    @Test func `many rows are deleted in batches`() async {
        let visits = (0 ..< 1200).map { record("https://example.com/\($0)") }
        await store.load()
        store.deleteVisits(Set(visits.prefix(1100).map(\.id)), profileID: profile)
        #expect(recordCount == 100)
        #expect(store.index(for: profile)?.entries.count == 100)
    }

    @Test func `clearing a period keeps older visits and other profiles`() async throws {
        let other = UUID()
        clock.now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 22)))
        record("https://avant-hier.example/")
        clock.now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 23)))
        record("https://hier.example/")
        clock.now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 18, hour: 8)))
        record("https://ce-matin.example/")
        record("https://autre-profil.example/", profileID: other)
        clock.advance(3 * 3600)
        record("https://maintenant.example/")
        await store.load()

        func keys() -> [String] {
            store.index(for: profile)?.entries.keys.sorted() ?? []
        }
        store.clear(.lastHour, profileID: profile)
        #expect(keys() == ["avant-hier.example", "ce-matin.example", "hier.example"])
        store.clear(.today, profileID: profile)
        #expect(keys() == ["avant-hier.example", "hier.example"])
        store.clear(.todayAndYesterday, profileID: profile)
        #expect(keys() == ["avant-hier.example"])
        store.clear(.allHistory, profileID: profile)
        #expect(keys().isEmpty)
        #expect(store.index(for: other)?.entries.keys.sorted() == ["autre-profil.example"])
        #expect(recordCount == 1)

        // Relu depuis la base : la même chose.
        let reopened = makeStore()
        await reopened.load()
        #expect(reopened.index(for: profile)?.entries.isEmpty == true)
        #expect(reopened.index(for: other)?.entries.count == 1)
    }

    @Test func `deleting a profile deletes its history`() async throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let history = try #require(session.history)
        let space = session.addProfile(named: "Travail")
        let profileID = try #require(space.record.profile?.id)
        let kept = try #require(session.spaces.first?.record.profile?.id)
        try history.recordVisit(url: #require(URL(string: "https://travail.example/")), title: nil, profileID: profileID, spaceID: space.id)
        try history.recordVisit(url: #require(URL(string: "https://perso.example/")), title: nil, profileID: kept, spaceID: nil)
        await history.load()

        try await session.deleteProfile(#require(space.record.profile))
        #expect(history.index(for: profileID)?.entries.isEmpty == true)
        #expect(history.index(for: kept)?.entries.count == 1)
        #expect(try session.container.mainContext.fetchCount(FetchDescriptor<HistoryRecord>()) == 1)
    }

    @Test func `private sessions have no history`() {
        #expect(BrowserSession.makePrivate().history == nil)
    }
}
