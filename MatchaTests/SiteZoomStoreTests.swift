import Foundation
@testable import Matcha
import Testing
import WebKit

/// Zoom retenu par site (tâche 5.4), sans page web : clé du site, réglage retenu ou oublié, enregistrement dans les
/// réglages, mémoire seule pour une fenêtre privée, pages suivies.
@MainActor
struct SiteZoomStoreTests {
    private let suiteName = "SiteZoomStoreTests-\(UUID().uuidString)"
    private let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suiteName))
    }

    /// Page sans vue web : seul compte son zoom recopié (`BrowserTab.pageZoom`).
    private func page() -> BrowserTab {
        BrowserTab(configuration: WKWebViewConfiguration())
    }

    @Test(arguments: [
        ("https://www.example.com/a?b#c", "example.com"),
        ("http://example.com:8080/", "example.com"),
        ("https://mail.google.com/", "google.com"),
        ("https://docs.google.com/", "google.com"),
        ("https://news.bbc.co.uk/", "bbc.co.uk"),
        ("https://EXAMPLE.com./", "example.com"),
        ("http://localhost:3000/", "localhost"),
        ("http://192.168.1.10/", "192.168.1.10"),
        ("file:///usr/share/doc/postfix/html/index.html", "file://"),
        ("file:///Users/moi/Documents/autre.html", "file://"),
    ])
    func `site key`(address: String, expected: String) {
        #expect(SiteZoomKey.key(for: URL(string: address)) == expected)
    }

    @Test(arguments: ["about:blank", "data:text/html,salut", "blob:https://example.com/1234", "obtest://pages/x"])
    func `no site key outside the web and local files`(address: String) {
        #expect(URL(string: address) != nil)
        #expect(SiteZoomKey.key(for: URL(string: address)) == nil)
        #expect(SiteZoomKey.key(for: nil) == nil)
    }

    @Test func `a site keeps its zoom and 100 percent forgets it`() {
        let store = SiteZoomStore(defaults: defaults)
        #expect(store.isPersistent)
        #expect(store.level(forSite: "example.com") == 1)
        #expect(store.level(forSite: nil) == 1)

        store.setLevel(1.25, forSite: "example.com")
        #expect(store.level(forSite: "example.com") == 1.25)
        #expect(store.levels == ["example.com": 1.25])
        #expect(defaults.dictionary(forKey: SiteZoomStore.defaultsKey) as? [String: Double] == ["example.com": 1.25])

        store.setLevel(1, forSite: "example.com")
        #expect(store.levels.isEmpty)
        #expect(defaults.object(forKey: SiteZoomStore.defaultsKey) == nil)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func `zooms survive a relaunch, unreadable values are ignored and others clamped`() {
        defaults.set(
            ["example.com": 1.5, "geant.org": 9.0, "nul.org": 1.0, "texte.org": "grand", "": 2.0],
            forKey: SiteZoomStore.defaultsKey,
        )
        let store = SiteZoomStore(defaults: defaults)
        #expect(store.levels == ["example.com": 1.5, "geant.org": 3])

        store.setLevel(0.75, forSite: "apple.com")
        let relaunched = SiteZoomStore(defaults: defaults)
        #expect(relaunched.level(forSite: "apple.com") == 0.75)
        #expect(relaunched.level(forSite: "example.com") == 1.5)
        defaults.removePersistentDomain(forName: suiteName)
    }

    @Test func `a private store writes nothing`() {
        let store = SiteZoomStore(defaults: nil)
        #expect(!store.isPersistent)
        store.setLevel(2, forSite: "example.com")
        #expect(store.level(forSite: "example.com") == 2)
        // Une autre session ne le voit pas.
        #expect(SiteZoomStore(defaults: nil).levels.isEmpty)
    }

    @Test func `private and test sessions keep zooms in memory`() throws {
        #expect(!BrowserSession.makePrivate().siteZooms.isPersistent)
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        #expect(!session.siteZooms.isPersistent)
        #expect(session.spaces.allSatisfy { $0.tabManager.siteZooms === session.siteZooms })
        let added = session.addSpace(in: session.profiles.first)
        #expect(added.tabManager.siteZooms === session.siteZooms)
        #expect(MiniWindowManager.forTests(session: session).siteZooms === session.siteZooms)
    }

    @Test func `a committed page takes its site zoom and follows its changes`() {
        let store = SiteZoomStore(defaults: nil)
        store.setLevel(1.5, forSite: "example.com")
        let first = page()
        let second = page()
        let other = page()
        store.pageDidCommit(first, url: URL(string: "https://example.com/a"))
        store.pageDidCommit(second, url: URL(string: "https://www.example.com/b"))
        store.pageDidCommit(other, url: URL(string: "https://apple.com/"))
        #expect(first.pageZoom == 1.5)
        #expect(second.pageZoom == 1.5)
        #expect(other.pageZoom == 1)

        // ⌘+ sur une page : son site retient le zoom, ses autres pages le prennent, pas celles d'un autre site.
        store.setZoom(1.75, for: first)
        #expect(store.level(forSite: "example.com") == 1.75)
        #expect(first.pageZoom == 1.75)
        #expect(second.pageZoom == 1.75)
        #expect(other.pageZoom == 1)

        // Une page qui change de site ne suit plus l'ancien, et prend le zoom du nouveau.
        store.pageDidCommit(second, url: URL(string: "https://apple.com/mac"))
        #expect(second.pageZoom == 1)
        store.setLevel(1.25, forSite: "example.com")
        #expect(first.pageZoom == 1.25)
        #expect(second.pageZoom == 1)
    }

    @Test func `a page without a site zooms alone and nothing is kept`() {
        let store = SiteZoomStore(defaults: nil)
        let blank = page()
        store.pageDidCommit(blank, url: URL(string: "about:blank"))
        store.setZoom(1.25, for: blank)
        #expect(blank.pageZoom == 1.25)
        #expect(store.levels.isEmpty)

        // Nouveau document sans site : 100 %.
        store.pageDidCommit(blank, url: URL(string: "data:text/html,salut"))
        #expect(blank.pageZoom == 1)
    }

    @Test func `the committed site wins over a new address still loading`() {
        let store = SiteZoomStore(defaults: nil)
        let tab = page()
        store.pageDidCommit(tab, url: URL(string: "https://example.com/"))
        // `tab.url` n'a pas d'adresse ici : seul compte le site du document affiché.
        store.setZoom(0.85, for: tab)
        #expect(store.levels == ["example.com": 0.85])
    }
}
