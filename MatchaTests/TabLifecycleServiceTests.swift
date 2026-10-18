import Foundation
@testable import Matcha
import Testing
import WebKit

/// Mise en veille des onglets d'une session (tâche 5.6) : ce qui est visible, quand et quoi mettre en veille.
@MainActor
struct TabLifecycleServiceTests {
    private let session: BrowserSession
    private let model: WindowModel
    private let service: TabLifecycleService
    private let clock = TestClock()
    private let fakes = FakeTabProbes()
    private let settings = SettingsBox()

    /// Réglage modifiable pendant un test.
    @MainActor
    final class SettingsBox {
        var delay: Duration? = .seconds(30 * 60)
    }

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        model = WindowModel(session: session, defaults: nil)
        service = session.tabLifecycle
        service.settings = { [settings] in TabSuspensionSettings(delay: settings.delay, checkInterval: .seconds(3600)) }
        service.now = { [clock] in clock.now }
        service.probes = fakes.probes()
        service.listensToMemoryPressure = false
        service.windowDidAppear(model)
    }

    private var manager: TabManager {
        model.space.tabManager
    }

    /// Ouvre `count` onglets ; le dernier est sélectionné, les autres sont cachés depuis maintenant.
    private func openTabs(_ count: Int) -> [BrowserTab] {
        let tabs = (0 ..< count).map { _ in manager.newTab() }
        service.refreshVisibility()
        return tabs
    }

    @Test func `hidden time follows the selection`() async throws {
        let tabs = openTabs(2)
        #expect(service.hiddenSince(tabs[0]) == fixedNow)
        #expect(service.hiddenSince(tabs[1]) == nil)

        clock.advance(60)
        manager.select(tabs[0])
        // Suivi des changements : noté à l'heure du changement, sans attendre une vérification.
        try await waitUntil { service.hiddenSince(tabs[1]) != nil }
        #expect(service.hiddenSince(tabs[1]) == fixedNow.addingTimeInterval(60))
        #expect(service.hiddenSince(tabs[0]) == nil)
    }

    @Test func `every pane of the displayed split is visible`() {
        let tabs = openTabs(3)
        #expect(manager.openInSplit(tabs[0]))
        service.refreshVisibility()
        #expect(service.hiddenSince(tabs[0]) == nil)
        #expect(service.hiddenSince(tabs[2]) == nil)
        #expect(service.hiddenSince(tabs[1]) == fixedNow)
    }

    @Test func `the selected tab of a Space that is not shown is hidden`() {
        let first = openTabs(1)[0]
        clock.advance(10)
        model.newSpace()
        service.refreshVisibility()
        #expect(service.hiddenSince(first) == fixedNow.addingTimeInterval(10))
    }

    @Test func `closing the window hides its tabs`() {
        let tab = openTabs(1)[0]
        #expect(service.hiddenSince(tab) == nil)
        service.windowDidDisappear(model)
        service.refreshVisibility()
        #expect(service.hiddenSince(tab) == fixedNow)
        service.windowDidAppear(model)
        service.refreshVisibility()
        #expect(service.hiddenSince(tab) == nil)
    }

    @Test func `tabs hidden longer than the delay are suspended, never the displayed one`() async {
        let tabs = openTabs(2)
        clock.advance(20 * 60)
        // Le deuxième onglet est caché depuis 20 minutes ; le nouveau est affiché.
        let shown = openTabs(1)[0]
        clock.advance(11 * 60)

        #expect(await service.check(.inactivity) == 1)
        #expect(tabs[0].suspension.isSuspended)
        #expect(tabs[0].suspension.snapshot != nil)
        #expect(!tabs[1].suspension.isSuspended)
        #expect(tabs[1].isLoaded)
        #expect(shown.isLoaded)
        #expect(fakes.snapshotRequests == 1)
        // Déjà en veille : rien de plus.
        #expect(await service.check(.inactivity) == 0)
    }

    /// Caméra et micro : `TabSuspensionPolicyTests` (WebKit ne les simule pas).
    @Test func `tabs playing media or asking for a permission are kept`() async throws {
        let tabs = openTabs(3)
        fakes.playing = try [ObjectIdentifier(#require(tabs[0].webView))]
        tabs[1].permissionPrompts.enqueue(.test([.camera], scope: nil, response: PermissionRecorder().response()))
        clock.advance(3600)

        #expect(await service.check(.memoryCritical) == 0)
        let allLoaded = tabs.allSatisfy(\.isLoaded)
        #expect(allLoaded)
    }

    /// Tâche 5.10 : l'icône haut-parleur suffit, sans attendre la réponse de WebKit.
    @Test func `a tab whose page plays sound is kept without asking WebKit`() async {
        let tabs = openTabs(2)
        tabs[0].audio.receive(PageAudioReport(frame: "main", isAudible: true))
        clock.advance(31 * 60)
        #expect(await service.check(.inactivity) == 0)
        #expect(tabs[0].isLoaded)
        #expect(fakes.mediaRequests == 0)

        // Plus de son : WebKit est de nouveau consulté.
        tabs[0].audio.reset()
        #expect(await service.check(.inactivity) == 1)
        #expect(fakes.mediaRequests == 1)
    }

    @Test func `never suspends nothing, even under memory pressure`() async {
        let tabs = openTabs(2)
        settings.delay = nil
        clock.advance(24 * 3600)
        #expect(await service.check(.inactivity) == 0)
        #expect(await service.check(.memoryCritical) == 0)
        #expect(tabs[0].isLoaded)
    }

    @Test func `a memory warning suspends the oldest half without snapshots`() async {
        // Chaque onglet est caché quand le suivant s'ouvre.
        var tabs = openTabs(2)
        clock.advance(300)
        tabs.append(contentsOf: openTabs(1))
        clock.advance(300)
        tabs.append(contentsOf: openTabs(1))
        clock.advance(270)
        tabs.append(contentsOf: openTabs(1))
        clock.advance(30)

        // Cachés depuis 15, 10 et 5 min, et 30 s : le dernier est épargné, la moitié (arrondie) des trois autres part.
        #expect(await service.check(.memoryWarning) == 2)
        #expect(tabs[0].suspension.isSuspended)
        #expect(tabs[1].suspension.isSuspended)
        #expect(tabs[2].isLoaded)
        #expect(tabs[3].isLoaded)
        #expect(tabs[4].isLoaded)
        #expect(fakes.snapshotRequests == 0)
    }

    @Test func `critical memory suspends every hidden tab and drops the snapshots`() async {
        let tabs = openTabs(3)
        clock.advance(31 * 60)
        #expect(await service.check(.inactivity) == 2)
        #expect(tabs[0].suspension.snapshot != nil)
        let late = manager.newTab()
        manager.select(tabs[2])
        service.refreshVisibility()

        #expect(await service.check(.memoryCritical) == 1)
        #expect(late.suspension.isSuspended)
        #expect(tabs[0].suspension.snapshot == nil)
        #expect(tabs[1].suspension.snapshot == nil)
        #expect(tabs[2].isLoaded)
    }

    /// Une alerte mémoire lance une vérification sans attendre la minuterie.
    @Test func `a memory alert runs a check right away`() async throws {
        let tabs = openTabs(2)
        service.schedule(.memoryCritical)
        try await waitUntil { tabs[0].suspension.isSuspended }
        #expect(tabs[1].isLoaded)
    }

    @Test func `a tab shown during its snapshot is not suspended`() async {
        let tabs = openTabs(2)
        clock.advance(31 * 60)
        fakes.duringSnapshot = { [manager] in manager.select(tabs[0]) }
        #expect(await service.check(.inactivity) == 0)
        #expect(tabs[0].isLoaded)
        #expect(!tabs[0].suspension.isSuspended)
    }

    /// L'aperçu n'est pas un onglet rangé : jamais mis en veille, et son onglet d'origine est affiché.
    @Test func `the Peek page and its source are never suspended`() async throws {
        let source = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        source.load(TestPages.url("source"))
        try await waitUntil { source.title == "source" && !source.isLoading }
        let peek = try #require(manager.openPeek(TestPages.url("apercu"), from: source))
        clock.advance(24 * 3600)
        #expect(await service.check(.memoryCritical) == 0)
        #expect(source.isLoaded)
        #expect(peek.tab.isLoaded)
    }

    /// Tâche 5.8 : tant que la fenêtre de connexion ouverte par un onglet l'est encore, l'onglet garde sa page, sans
    /// quoi `window.opener` ne la retrouverait plus.
    @Test func `a tab with an open sign-in window is never suspended`() async throws {
        session.popupWindows.prepareForTests()
        let tabs = openTabs(2)
        let opener = tabs[0]
        let popupWebView = try #require(manager.coordinator.webView(
            opener.loadedWebView,
            createWebViewWith: opener.configuration,
            for: FakeNavigationAction(url: TestPages.url("connexion"), modifierFlags: []),
            windowFeatures: FakeWindowFeatures(width: 500, height: 600),
        ))
        let popup = try #require(session.popupWindows.window(for: popupWebView))
        clock.advance(3600)

        #expect(await service.check(.memoryCritical) == 0)
        #expect(opener.isLoaded)

        popup.close()
        #expect(await service.check(.memoryCritical) == 1)
        #expect(opener.suspension.isSuspended)
    }

    /// Un favori est commun aux Spaces du profil : un seul onglet, examiné une fois.
    @Test func `a favorite shared by two Spaces is shown in the displayed one`() async {
        let favorite = openTabs(1)[0]
        manager.setPlace(favorite, to: .favorite)
        model.newSpace()
        manager.select(favorite)
        clock.advance(24 * 3600)
        #expect(await service.check(.memoryCritical) == 0)
        #expect(favorite.isLoaded)
    }
}
