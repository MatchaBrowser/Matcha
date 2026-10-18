import Foundation
@testable import Matcha
import Testing

/// Exceptions du bloqueur (tâche 6.2), sans page web : site d'une adresse, sites relus, enregistrement dans les
/// réglages ou en mémoire seulement ; vues d'une session (enregistrées, ou en mémoire pour une fenêtre privée).
@MainActor
struct ContentBlockerExceptionsTests {
    private let suiteName = "ContentBlockerExceptionsTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    @Test(arguments: [
        ("https://www.example.com/a?b#c", "example.com"),
        ("http://example.com:8080/", "example.com"),
        ("https://mail.google.com/", "google.com"),
        ("https://news.bbc.co.uk/", "bbc.co.uk"),
        ("https://EXAMPLE.com./", "example.com"),
        ("http://localhost:3000/", "localhost"),
        ("http://192.168.1.10/", "192.168.1.10"),
    ])
    func `the site of an address is its registrable domain`(address: String, expected: String) {
        #expect(ContentBlockerExceptions.site(for: URL(string: address)) == expected)
    }

    @Test(arguments: ["about:blank", "file:///Users/moi/page.html", "obtest://pages/x", "data:text/html,salut"])
    func `no site outside the web`(address: String) {
        #expect(ContentBlockerExceptions.site(for: URL(string: address)) == nil)
    }

    @Test func `sites are normalized and odd values refused`() {
        #expect(ContentBlockerExceptions.normalized(" Example.COM. ") == "example.com")
        for value in ["", "  ", "exa mple.com", "example.com/page", "https://example.com", ".example.com", "a@b.com"] {
            #expect(ContentBlockerExceptions.normalized(value) == nil)
        }
    }

    @Test func `exceptions are saved in the settings and read back`() {
        let exceptions = ContentBlockerExceptions(defaults: defaults)
        #expect(exceptions.set(true, forSite: "b.com"))
        #expect(exceptions.set(true, forSite: "A.com"))
        #expect(!exceptions.set(true, forSite: "a.com"))
        #expect(defaults.stringArray(forKey: ContentBlockerExceptions.defaultsKey) == ["a.com", "b.com"])
        #expect(ContentBlockerExceptions(defaults: defaults).sortedSites == ["a.com", "b.com"])
        #expect(exceptions.set(false, forSite: "a.com"))
        #expect(exceptions.set(false, forSite: "b.com"))
        #expect(!exceptions.set(false, forSite: "b.com"))
        #expect(defaults.object(forKey: ContentBlockerExceptions.defaultsKey) == nil)
    }

    @Test func `odd saved values are ignored`() {
        defaults.set(["example.com", "pas un site", "", "EXAMPLE.com"], forKey: ContentBlockerExceptions.defaultsKey)
        #expect(ContentBlockerExceptions(defaults: defaults).sortedSites == ["example.com"])
    }

    @Test func `without settings nothing is written`() {
        let exceptions = ContentBlockerExceptions(defaults: nil)
        exceptions.set(true, forSite: "example.com")
        #expect(exceptions.contains("example.com"))
        #expect(defaults.object(forKey: ContentBlockerExceptions.defaultsKey) == nil)
    }

    @Test func `the main session saves its exceptions`() {
        let service = ContentBlockerService(defaults: defaults)
        let scope = ContentBlockerScope(service: service, savesExceptions: true)
        scope.setBlocks(false, onSite: "Example.com")
        #expect(scope.isExcepted(site: "example.com"))
        #expect(service.exceptions.contains("example.com"))
        #expect(defaults.stringArray(forKey: ContentBlockerExceptions.defaultsKey) == ["example.com"])
        scope.setBlocks(true, onSite: "example.com")
        #expect(!scope.isExcepted(site: "example.com"))
        #expect(service.exceptions.sites.isEmpty)
    }

    /// Fenêtre privée : elle suit les exceptions enregistrées, mais ses changements restent à elle.
    @Test func `a private session keeps its changes in memory`() {
        let service = ContentBlockerService(defaults: defaults)
        service.setException(true, forSite: "saved.com")
        let main = ContentBlockerScope(service: service, savesExceptions: true)
        let privateScope = ContentBlockerScope(service: service, savesExceptions: false)
        #expect(privateScope.isExcepted(site: "saved.com"))

        privateScope.setBlocks(false, onSite: "visited.com")
        privateScope.setBlocks(true, onSite: "saved.com")
        #expect(privateScope.isExcepted(site: "visited.com"))
        #expect(!privateScope.isExcepted(site: "saved.com"))
        #expect(!main.isExcepted(site: "visited.com"))
        #expect(main.isExcepted(site: "saved.com"))
        #expect(defaults.stringArray(forKey: ContentBlockerExceptions.defaultsKey) == ["saved.com"])
    }

    /// Une fenêtre privée et une base de test n'enregistrent jamais d'exception ; onglets et fenêtres de connexion
    /// passent par le bloqueur de leur session.
    @Test func `sessions give their scope to their pages`() throws {
        let privateSession = BrowserSession.makePrivate()
        #expect(!privateSession.contentBlocking.savesExceptions)
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        #expect(!session.contentBlocking.savesExceptions)
        #expect(session.contentBlocking.service === ContentBlockerService.shared)
        #expect(session.spaces.allSatisfy { $0.tabManager.contentBlocking === session.contentBlocking })
        #expect(session.popupWindows.contentBlocking === session.contentBlocking)
        let profile: ProfileRecord = try #require(session.profiles.first)
        let space = session.addSpace(in: profile)
        #expect(space.tabManager.contentBlocking === session.contentBlocking)
    }

    @Test func `the global switch is saved and on by default`() {
        #expect(ContentBlockerService(defaults: nil).isEnabled)
        let service = ContentBlockerService(defaults: defaults)
        #expect(service.isEnabled)
        service.isEnabled = false
        #expect(defaults.object(forKey: BrowserSettings.Key.blocksAdsAndTrackers) as? Bool == false)
        #expect(!ContentBlockerService(defaults: defaults).isEnabled)
        #expect(!BrowserSettings.blocksAdsAndTrackers(in: defaults))
        defaults.set("YES", forKey: BrowserSettings.Key.blocksAdsAndTrackers)
        #expect(BrowserSettings.blocksAdsAndTrackers(in: defaults))
    }
}
