import Foundation
@testable import Matcha
import Testing

/// Première synchro d'un Mac (tâche 7.4, `SYNC.md` § 5) : tout envoyer, prendre les données synchronisées, fusionner,
/// remplacer d'un côté ou de l'autre.
@MainActor
struct SyncFirstSyncTests {
    private let server = InMemorySyncServer()
    private let searchEngine = SyncIdentifier.setting("searchEngine")
    private let appearance = SyncIdentifier.setting("appearance")

    private func setting(_ key: String, _ value: String) -> SyncFields {
        .setting(SyncSettingFields(key: key, value: .string(value)))
    }

    /// Un Mac, son profil et son Space.
    private struct Setup {
        let mac: SimulatedMac
        let profile: UUID
        let space: UUID
    }

    /// Un premier Mac synchronisé, avec son profil, son Space et son moteur de recherche.
    private func firstMac() async throws -> Setup {
        let mac = SimulatedMac(server: server)
        let profile = mac.addProfile("Personnel")
        let space = mac.addSpace("Perso", profile: profile)
        mac.store.items[searchEngine] = setting("searchEngine", "google")
        try await mac.sync()
        return Setup(mac: mac, profile: profile, space: space)
    }

    /// Un second Mac avec ses propres données.
    private func secondMac() -> Setup {
        let mac = SimulatedMac(server: server)
        let profile = mac.addProfile("Travail")
        let space = mac.addSpace("Bureau", profile: profile)
        mac.store.items[searchEngine] = setting("searchEngine", "bing")
        return Setup(mac: mac, profile: profile, space: space)
    }

    @Test func `the first Mac sends everything`() async throws {
        let setup = try await firstMac()
        let (mac, profile, space) = (setup.mac, setup.profile, setup.space)
        #expect(await server.content(of: profile)?.readableFields == mac.store.items[profile])
        #expect(await server.content(of: space)?.readableFields == mac.store.items[space])
        #expect(await server.counter == 3)
    }

    @Test func `a Mac with only its first launch takes the synced data`() async throws {
        let setup = try await firstMac()
        let (first, profile, space) = (setup.mac, setup.profile, setup.space)
        let own = secondMac()
        let (second, ownProfile, ownSpace) = (own.mac, own.profile, own.space)
        second.store.hasOnlyFirstLaunchData = true
        second.store.items[searchEngine] = nil
        second.store.items[appearance] = setting("appearance", "dark")
        var asked = false
        second.engine.chooseFirstSync = {
            asked = true
            return .merge
        }
        try await second.sync()
        #expect(!asked)
        #expect(second.store.items[profile] == first.store.items[profile])
        #expect(second.store.items[space] != nil)
        #expect(second.store.items[ownProfile] == nil)
        #expect(second.store.items[ownSpace] == nil)
        #expect(await server.content(of: ownSpace) == nil)
        // Un réglage propre à ce Mac reste, sans partir.
        #expect(second.store.items[appearance] == setting("appearance", "dark"))
        #expect(await server.content(of: appearance) == nil)
    }

    @Test func `merging keeps both, synced settings win`() async throws {
        let setup = try await firstMac()
        let (first, profile) = (setup.mac, setup.profile)
        let own = secondMac()
        let (second, ownProfile, ownSpace) = (own.mac, own.profile, own.space)
        second.store.items[appearance] = setting("appearance", "dark")
        var asked = false
        second.engine.chooseFirstSync = {
            asked = true
            return .merge
        }
        try await second.sync()
        #expect(asked)
        #expect(second.store.items[profile] != nil)
        #expect(second.store.items[ownSpace] != nil)
        #expect(second.store.items[searchEngine] == setting("searchEngine", "google"))

        try await first.sync()
        #expect(first.store.items[ownProfile] == second.store.items[ownProfile])
        #expect(first.store.items[appearance] == setting("appearance", "dark"))
        #expect(first.store.items == second.store.items)
    }

    @Test func `replacing this Mac's data`() async throws {
        let first = try await firstMac().mac
        let own = secondMac()
        let (second, ownProfile, ownSpace) = (own.mac, own.profile, own.space)
        let zoom = SyncIdentifier.siteZoom("example.com")
        second.store.items[zoom] = .siteZoom(SyncSiteZoomFields(site: "example.com", level: 1.5))
        second.store.items[appearance] = setting("appearance", "dark")
        second.engine.chooseFirstSync = { .replaceLocal }
        try await second.sync()
        #expect(second.store.items[ownProfile] == nil)
        #expect(second.store.items[ownSpace] == nil)
        #expect(second.store.items[zoom] == nil)
        #expect(second.store.items[searchEngine] == setting("searchEngine", "google"))
        #expect(second.store.items[appearance] != nil)
        #expect(try await second.sync()?.sent == 0)
        try await first.sync()
        #expect(first.store.items[appearance] == nil)
    }

    @Test func `replacing the synced data`() async throws {
        let setup = try await firstMac()
        let (first, profile, space) = (setup.mac, setup.profile, setup.space)
        let own = secondMac()
        let (second, ownProfile, ownSpace) = (own.mac, own.profile, own.space)
        second.engine.chooseFirstSync = { .replaceRemote }
        try await second.sync()
        #expect(second.store.items[profile] == nil)
        #expect(await server.content(of: profile)?.deleted == true)
        #expect(await server.content(of: searchEngine)?.readableFields == setting("searchEngine", "bing"))

        try await first.sync()
        #expect(first.store.items[profile] == nil)
        #expect(first.store.items[space] == nil)
        #expect(first.store.items[ownProfile] == second.store.items[ownProfile])
        #expect(first.store.items[ownSpace] == second.store.items[ownSpace])
        #expect(first.store.items[searchEngine] == setting("searchEngine", "bing"))
    }
}
