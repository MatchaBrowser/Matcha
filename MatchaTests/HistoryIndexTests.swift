import Foundation
@testable import Matcha
import Testing

/// Visite de test : `minutesAgo` avant `fixedNow`.
func historyVisit(_ address: String, title: String? = nil, minutesAgo: Double = 0, id: UUID = UUID()) -> HistoryVisit {
    HistoryVisit(id: id, url: URL(string: address)!, title: title, date: fixedNow.addingTimeInterval(-minutesAgo * 60))
}

/// Historique d'un profil en mémoire (tâche 5.5) : regroupement par adresse, titres, suppressions.
struct HistoryIndexTests {
    @Test func `visits of the same page are grouped by address key`() throws {
        let index = HistoryIndex(visits: [
            historyVisit("https://www.example.com/", title: "Example", minutesAgo: 30),
            historyVisit("http://example.com", title: nil, minutesAgo: 10),
            historyVisit("https://example.com/autre", title: "Autre", minutesAgo: 20),
        ])
        #expect(index.visits.count == 3)
        #expect(Set(index.entries.keys) == ["example.com", "example.com/autre"])
        let entry = try #require(index.entries["example.com"])
        #expect(entry.visitCount == 2)
        #expect(entry.lastVisit == fixedNow.addingTimeInterval(-600))
        // Adresse de la dernière visite ; titre de la dernière visite qui en a un.
        #expect(entry.url.absoluteString == "http://example.com")
        #expect(entry.title == "Example")
        #expect(entry.historyEntry == HistoryEntry(url: entry.url, title: "Example", visitCount: 2, lastVisit: entry.lastVisit))
    }

    @Test func `a newer title replaces the older one`() {
        var index = HistoryIndex(visits: [historyVisit("https://example.com/", title: "Ancien", minutesAgo: 30)])
        let newer = historyVisit("https://example.com/", title: "Nouveau", minutesAgo: 5)
        index.insert(newer)
        #expect(index.entries["example.com"]?.title == "Nouveau")

        // Le titre d'une visite change (titre arrivé tard) ; vide, il ne compte plus.
        index.setTitle("Renommé", ofVisit: newer.id)
        #expect(index.entries["example.com"]?.title == "Renommé")
        index.setTitle("  ", ofVisit: newer.id)
        #expect(index.visits[newer.id]?.title == nil)
        #expect(index.entries["example.com"]?.title == "Ancien")
        // Visite inconnue : rien.
        index.setTitle("Fantôme", ofVisit: UUID())
        #expect(index.entries["example.com"]?.title == "Ancien")
    }

    @Test func `inserting the same visit twice counts it once`() {
        let visit = historyVisit("https://example.com/", title: "Exemple")
        var index = HistoryIndex(visits: [visit])
        index.insert(visit)
        #expect(index.entries["example.com"]?.visitCount == 1)
        #expect(index.visits.count == 1)
    }

    @Test func `refreshing a visit moves its date and keeps its title without a new one`() throws {
        let visit = historyVisit("https://example.com/", title: "Exemple", minutesAgo: 1)
        var index = HistoryIndex(visits: [visit])
        index.refresh(visit: visit.id, date: fixedNow, title: nil)
        let entry = try #require(index.entries["example.com"])
        #expect(entry.visitCount == 1)
        #expect(entry.lastVisit == fixedNow)
        #expect(entry.title == "Exemple")
        index.refresh(visit: visit.id, date: fixedNow, title: "Rechargé")
        #expect(index.entries["example.com"]?.title == "Rechargé")
    }

    @Test func `removing visits recomputes their address`() throws {
        let old = historyVisit("https://example.com/", title: "Ancien", minutesAgo: 60)
        let recent = historyVisit("https://www.example.com/", title: "Récent", minutesAgo: 1)
        let other = historyVisit("https://apple.com/", title: "Apple", minutesAgo: 2)
        var index = HistoryIndex(visits: [old, recent, other])

        index.remove([recent.id])
        let entry = try #require(index.entries["example.com"])
        #expect(entry.visitCount == 1)
        #expect(entry.lastVisit == old.date)
        #expect(entry.title == "Ancien")
        #expect(entry.url.absoluteString == "https://example.com/")

        index.remove([old.id, UUID()])
        #expect(index.entries["example.com"] == nil)
        #expect(index.entries.keys.sorted() == ["apple.com"])
        index.remove([other.id])
        #expect(index.isEmpty)
        #expect(index.entries.isEmpty)
    }

    @Test func `removing since a date keeps older visits`() {
        var index = HistoryIndex(visits: [
            historyVisit("https://example.com/", minutesAgo: 120),
            historyVisit("https://example.com/", minutesAgo: 59),
            historyVisit("https://apple.com/", minutesAgo: 60),
            // Datée dans le futur (heure du Mac changée) : effacée aussi.
            historyVisit("https://future.example/", minutesAgo: -30),
        ])
        index.remove(since: fixedNow.addingTimeInterval(-3600))
        #expect(index.entries.keys.sorted() == ["example.com"])
        #expect(index.entries["example.com"]?.visitCount == 1)
    }

    @Test func `changes replayed after loading never count twice`() {
        let profile = UUID()
        let visit = historyVisit("https://example.com/", title: nil, minutesAgo: 1)
        let changes: [HistoryChange] = [
            .insert(visit, profileID: profile),
            .setTitle("Exemple", visitID: visit.id, profileID: profile),
            .refresh(visitID: visit.id, date: fixedNow, title: nil, profileID: profile),
        ]
        // Lecture qui a déjà vu la visite et son titre, puis les changements rejoués.
        var loaded: [UUID?: HistoryIndex] = [profile: HistoryIndex(visits: [historyVisit(
            "https://example.com/", title: "Exemple", minutesAgo: 1, id: visit.id,
        )])]
        changes.forEach { $0.apply(to: &loaded) }
        // Lecture qui ne l'a pas vue.
        var empty: [UUID?: HistoryIndex] = [:]
        changes.forEach { $0.apply(to: &empty) }
        for indexes in [loaded, empty] {
            #expect(indexes[profile]?.entries["example.com"]?.visitCount == 1)
            #expect(indexes[profile]?.entries["example.com"]?.title == "Exemple")
            #expect(indexes[profile]?.entries["example.com"]?.lastVisit == fixedNow)
        }

        HistoryChange.remove([visit.id], profileID: profile).apply(to: &loaded)
        HistoryChange.remove([visit.id], profileID: profile).apply(to: &loaded)
        #expect(loaded[profile] == nil)
    }

    @Test func `removing a profile or a period only touches that profile`() {
        let first = UUID()
        let second = UUID()
        var indexes: [UUID?: HistoryIndex] = [
            first: HistoryIndex(visits: [historyVisit("https://a.example/", minutesAgo: 10)]),
            second: HistoryIndex(visits: [historyVisit("https://b.example/", minutesAgo: 10)]),
            nil: HistoryIndex(visits: [historyVisit("https://c.example/", minutesAgo: 10)]),
        ]
        HistoryChange.removeSince(fixedNow.addingTimeInterval(-3600), profileID: first).apply(to: &indexes)
        #expect(indexes[first] == nil)
        #expect(indexes[second]?.entries.keys.sorted() == ["b.example"])
        HistoryChange.removeSince(nil, profileID: nil).apply(to: &indexes)
        #expect(indexes.keys.map(\.self) == [second])
    }

    @Test func `character mask only tells what cannot match`() {
        // Textes déjà repliés, comme ceux de la barre de commande.
        let mask = HistoryCharacterMask(["ecole 42", "node.js"])
        #expect(mask.contains(HistoryCharacterMask(["ecole"])))
        #expect(mask.contains(HistoryCharacterMask(["42 node"])))
        // Ponctuation et espaces ne comptent pas.
        #expect(mask.contains(HistoryCharacterMask(["n.o-d e/"])))
        #expect(!mask.contains(HistoryCharacterMask(["z"])))
        #expect(!mask.contains(HistoryCharacterMask(["école"])))
        #expect(HistoryCharacterMask([]).contains(HistoryCharacterMask(["  ./"])))
    }
}
