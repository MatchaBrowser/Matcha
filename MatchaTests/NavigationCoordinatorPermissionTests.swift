import Foundation
@testable import Matcha
import Testing
import WebKit

/// Demandes de caméra et de micro reçues par le délégué (tâche 5.2), avec de vraies vues web. WebKit ne permet pas de
/// créer un `WKSecurityOrigin` : les tests passent par `requestPermission`, que la méthode du délégué appelle après
/// conversion. Une vraie demande `getUserMedia` ferait apparaître la demande d'accès de macOS : contrôle manuel.
@MainActor
struct NavigationCoordinatorPermissionTests {
    private let session: BrowserSession
    private let recorder = PermissionRecorder()

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
    }

    private var space: SpaceSession {
        session.spaces[0]
    }

    private var manager: TabManager {
        space.tabManager
    }

    private var scope: SitePermissionScope {
        manager.sitePermissions!
    }

    /// Onglet sélectionné sur la page locale `name`, une fois chargée.
    private func openTab(_ name: String = "visio") async throws -> BrowserTab {
        let tab = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(TestPages.url(name))
        try await waitUntil { tab.title == name && !tab.isLoading }
        return tab
    }

    private func request(
        _ kinds: Set<SitePermissionKind>,
        from tab: BrowserTab,
        origin: SiteOrigin? = TestOrigins.meet,
        frame: SiteOrigin? = TestOrigins.meet,
        coordinator: NavigationCoordinator? = nil,
    ) {
        (coordinator ?? manager.coordinator).requestPermission(
            kinds,
            origin: origin,
            frameOrigin: frame,
            in: tab.loadedWebView,
            response: recorder.response(),
        )
    }

    @Test func `the coordinator answers WebKit media capture requests`() {
        let selector = #selector(WKUIDelegate.webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:))
        #expect(manager.coordinator.responds(to: selector))
        #expect(NavigationCoordinator.kinds(of: .camera) == [.camera])
        #expect(NavigationCoordinator.kinds(of: .microphone) == [.microphone])
        #expect(NavigationCoordinator.kinds(of: .cameraAndMicrophone) == [.camera, .microphone])
    }

    @Test func `saved decisions answer at once, without a banner`() async throws {
        let tab = try await openTab()
        scope.set(.allow, for: .camera, origin: TestOrigins.meet)
        scope.set(.deny, for: .microphone, origin: TestOrigins.meet)

        request([.camera], from: tab)
        request([.microphone], from: tab)
        request([.camera, .microphone], from: tab)
        #expect(recorder.answers == [true, false, false])
        #expect(tab.permissionPrompts.requests.isEmpty)
    }

    @Test func `an undecided request waits in the banner of the tab that asked`() async throws {
        let other = try await openTab("autre")
        let tab = try await openTab()
        scope.set(.allow, for: .microphone, origin: TestOrigins.meet)

        request([.camera, .microphone], from: tab)
        #expect(recorder.answers.isEmpty)
        #expect(other.permissionPrompts.requests.isEmpty)
        let pending = try #require(tab.permissionPrompts.current)
        #expect(pending.origin == TestOrigins.meet)
        #expect(pending.requested == [.camera, .microphone])
        #expect(pending.asked == [.camera])
        #expect(pending.frameName == nil)
        #expect(pending.canRemember)

        tab.permissionPrompts.answer(.alwaysAllow)
        #expect(recorder.answers == [true])
        #expect(scope.decisions(for: TestOrigins.meet) == [.camera: .allow, .microphone: .allow])
        // La prochaine fois, plus de bandeau.
        request([.camera, .microphone], from: tab)
        #expect(recorder.answers == [true, true])
    }

    @Test func `the banner names an embedded frame from another website`() async throws {
        let tab = try await openTab()
        request([.camera], from: tab, frame: TestOrigins.other)
        #expect(tab.permissionPrompts.current?.frameName == "other.example.org")
        // La décision vaut pour la page principale.
        tab.permissionPrompts.answer(.deny)
        #expect(scope.decisions(for: TestOrigins.meet) == [.camera: .deny])
        #expect(scope.decisions(for: TestOrigins.other).isEmpty)
    }

    @Test func `a new page in the tab denies what waits`() async throws {
        let tab = try await openTab()
        request([.camera], from: tab)
        tab.load(TestPages.url("ailleurs"))
        try await waitUntil { recorder.answers == [false] }
        #expect(tab.permissionPrompts.requests.isEmpty)
        #expect(scope.store.entries.isEmpty)
    }

    @Test func `closing the tab denies what waits`() async throws {
        let tab = try await openTab()
        request([.camera], from: tab)
        manager.close(tab)
        #expect(recorder.answers == [false])

        // Un épinglé fermé se décharge : même refus.
        let pinned = try await openTab("epingle")
        manager.setPlace(pinned, to: .pinned)
        request([.microphone], from: pinned)
        manager.close(pinned)
        #expect(recorder.answers == [false, false])
    }

    @Test func `a page that is not hosted is denied`() {
        let stray = BrowserTab(configuration: TestPages.configuration())
        manager.coordinator.requestPermission(
            [.camera],
            origin: TestOrigins.meet,
            frameOrigin: nil,
            in: stray.loadedWebView,
            response: recorder.response(),
        )
        #expect(recorder.answers == [false])
    }

    @Test func `the Peek page asks in its own banner and closing Peek denies`() async throws {
        let source = try await openTab()
        let peek = try #require(manager.openPeek(TestPages.url("apercu"), from: source))
        try await waitUntil { peek.tab.title == "apercu" && !peek.tab.isLoading }

        request([.camera], from: peek.tab)
        #expect(peek.tab.permissionPrompts.requests.count == 1)
        #expect(source.permissionPrompts.requests.isEmpty)
        manager.closePeek()
        #expect(recorder.answers == [false])
    }

    @Test func `a mini window remembers decisions for its profile`() async throws {
        let work = session.addProfile(named: "Travail")
        let model = WindowModel(session: session, defaults: nil)
        model.select(work)
        let miniWindows = MiniWindowManager.forTests(session: session)
        miniWindows.linkMainWindow(FakeMainWindowLink(windowModel: model))
        let mini = miniWindows.openNew(loading: TestPages.url("mini"), source: .link)
        try await waitUntil { mini.tab.title == "mini" && !mini.tab.isLoading }

        request([.camera], from: mini.tab, coordinator: miniWindows.coordinator)
        mini.tab.permissionPrompts.answer(.alwaysAllow)
        #expect(recorder.answers == [true])
        #expect(session.sitePermissions.decision(.camera, for: TestOrigins.meet, profileID: work.record.profile?.id) == .allow)
        #expect(scope.decision(.camera, for: TestOrigins.meet) == nil)

        request([.microphone], from: mini.tab, coordinator: miniWindows.coordinator)
        mini.close()
        #expect(recorder.answers == [true, false])
    }

    @Test func `a private window never writes its decisions`() async throws {
        let privateSession = BrowserSession.makePrivate()
        let privateManager = privateSession.spaces[0].tabManager
        let tab = privateManager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        tab.load(TestPages.url("prive"))
        try await waitUntil { tab.title == "prive" && !tab.isLoading }

        request([.camera], from: tab, coordinator: privateManager.coordinator)
        #expect(tab.permissionPrompts.current?.canRemember == true)
        tab.permissionPrompts.answer(.alwaysAllow)
        request([.camera], from: tab, coordinator: privateManager.coordinator)
        #expect(recorder.answers == [true, true])
        #expect(!privateSession.sitePermissions.isPersistent)
        #expect(session.sitePermissions.entries.isEmpty)
    }
}
