import AppKit
@testable import Matcha
import Testing
import WebKit

/// Relève le prochain menu contextuel dès qu'il s'ouvre, tel qu'il s'affiche (après la réécriture de Matcha), y
/// choisit un élément de Matcha comme l'utilisateur (`performActionForItem`), puis le ferme. Tout se passe pendant le
/// suivi du menu, alors que WebKit l'affiche encore. Tout autre menu qui s'ouvrirait ensuite est fermé aussitôt.
@MainActor
final class ContextMenuDriver: NSObject {
    private let choice: PageMenuItem?
    private var menu: NSMenu?
    private var observers: [any NSObjectProtocol] = []
    /// Identifiants des éléments du menu (nil : séparateur).
    private(set) var identifiers: [String?] = []
    /// Éléments de Matcha, à leur place (nil : élément de WebKit).
    private(set) var choices: [PageMenuItem?] = []
    /// Le menu a été relevé, puis s'est fermé.
    private(set) var didClose = false

    var didOpen: Bool {
        menu != nil
    }

    init(choosing choice: PageMenuItem?) {
        self.choice = choice
        super.init()
        observe(NSMenu.didBeginTrackingNotification) { $0.menuDidOpen($1) }
        observe(NSMenu.didEndTrackingNotification) { driver, menu in
            if menu === driver.menu, !driver.identifiers.isEmpty {
                driver.didClose = true
            }
        }
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func observe(_ name: Notification.Name, _ handle: @escaping @MainActor (ContextMenuDriver, NSMenu) -> Void) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
            // Avis donné sur la file principale (`queue: .main`) : le menu n'en sort pas.
            nonisolated(unsafe) let menu = notification.object as? NSMenu
            MainActor.assumeIsolated {
                if let self, let menu {
                    handle(self, menu)
                }
            }
        })
    }

    private func menuDidOpen(_ menu: NSMenu) {
        guard self.menu == nil else {
            menu.cancelTracking()
            return
        }
        self.menu = menu
        // L'avis précède `willOpenMenu` (constaté) : le menu est relevé au tour suivant, pendant son suivi, où la
        // boucle principale tourne dans ce mode.
        perform(#selector(chooseAndClose), with: nil, afterDelay: 0, inModes: [.eventTracking, .default])
    }

    @objc private func chooseAndClose() {
        guard let menu else {
            return
        }
        identifiers = menu.items.map { $0.identifier?.rawValue }
        choices = menu.items.map { ($0.representedObject as? PageMenuChoice)?.item }
        if let choice, let index = menu.items.firstIndex(where: { ($0.representedObject as? PageMenuChoice)?.item == choice }) {
            menu.performActionForItem(at: index)
        }
        menu.cancelTracking()
    }
}

/// Menu contextuel des pages (tâche 5.9) sur un vrai menu de WebKit, ouvert par un clic droit simulé dans une vraie
/// vue web : identifiants relevés, élément de WebKit déclenché, fenêtre rangée. WebKit n'ouvre son menu que pour une
/// vue web dans une fenêtre affichée : la fenêtre est placée hors de tout écran ; le menu apparaît un instant.
@MainActor
@Suite(.serialized)
final class PageMenuIntegrationTests {
    private let manager = TabManager(websiteDataStore: .nonPersistent())
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
        styleMask: [.titled],
        backing: .buffered,
        defer: false,
    )
    private static let link = "<a href='\(TestPages.url("cible").absoluteString)' style='display:block;height:600px'>lien</a>"

    init() {
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
    }

    isolated deinit {
        window.orderOut(nil)
    }

    /// Onglet sélectionné qui affiche `body` (sans marge), seul dans la fenêtre, une fois la page visible et mise en
    /// page à la taille de la fenêtre, avec `element` au milieu.
    private func showPage(_ body: String, element: String) async throws -> BrowserTab {
        let page = manager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
        let webView = page.loadedWebView
        webView.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        window.contentView = webView
        window.orderFront(nil)
        page.load(TestPages.url("source", body: "<style>body{margin:0}</style>" + body))
        try await waitUntil { page.title == "source" && !page.isLoading }
        let script = "document.visibilityState == 'visible' && document.elementFromPoint(400, 300)?.tagName == '\(element)'"
        let deadline = ContinuousClock.now + .seconds(5)
        while try await webView.evaluateJavaScript(script) as? Bool != true, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        return page
    }

    /// Clic droit au milieu de la page ; le menu est relevé, `choice` y est choisi, puis il se ferme. Juste après un
    /// autre menu, WebKit peut ne pas ouvrir le sien (constaté) : le clic est refait, trois fois au plus.
    private func rightClick(choosing choice: PageMenuItem?) async throws -> ContextMenuDriver {
        let driver = ContextMenuDriver(choosing: choice)
        for _ in 1 ... 3 {
            try sendRightClick()
            if await (try? waitUntil(timeout: .seconds(2)) { driver.didOpen }) != nil {
                break
            }
        }
        try await waitUntil { driver.didClose }
        // Le temps que WebKit et AppKit en finissent avec ce menu avant le suivant.
        try await Task.sleep(for: .milliseconds(300))
        return driver
    }

    private func sendRightClick() throws {
        for type in [NSEvent.EventType.rightMouseDown, .rightMouseUp] {
            let event = try #require(NSEvent.mouseEvent(
                with: type,
                location: NSPoint(x: 400, y: 300),
                modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: type == .rightMouseDown ? 1 : 0,
            ))
            window.sendEvent(event)
        }
    }

    @Test func `the link menu of WebKit gets new tab and Peek in place of new window`() async throws {
        _ = try await showPage(Self.link, element: "A")
        let driver = try await rightClick(choosing: nil)

        #expect(driver.choices.compactMap(\.self) == [.openLinkInNewTab, .openLinkInPeek])
        let openLink = try #require(driver.identifiers.firstIndex(of: "WKMenuItemIdentifierOpenLink"))
        #expect(driver.choices[openLink + 1] == .openLinkInNewTab)
        #expect(!driver.identifiers.contains("WKMenuItemIdentifierOpenLinkInNewWindow"))
        #expect(driver.identifiers.contains("WKMenuItemIdentifierCopyLink"))
        #expect(driver.identifiers.contains("WKMenuItemIdentifierDownloadLinkedFile"))
    }

    @Test func `open link in new tab from the menu adds a background tab`() async throws {
        let page = try await showPage(Self.link, element: "A")
        _ = try await rightClick(choosing: .openLinkInNewTab)

        try await waitUntil { manager.tabs.count == 2 }
        let added = manager.tabs[1]
        #expect(manager.tabs[0] === page)
        #expect(manager.selectedTab === page)
        #expect(manager.peek == nil)
        try await waitUntil { added.title == "cible" && !added.isLoading }
        #expect((page.webView as? BrowserWebView)?.pageMenuIntent.intent == nil)
    }

    @Test func `open link in Peek from the menu opens Peek`() async throws {
        let page = try await showPage(Self.link, element: "A")
        _ = try await rightClick(choosing: .openLinkInPeek)

        try await waitUntil { manager.peek != nil }
        let peek = try #require(manager.peek)
        #expect(peek.sourceTabID == page.id)
        try await waitUntil { peek.tab.title == "cible" && !peek.tab.isLoading }
        #expect(manager.tabs.count == 1)
    }

    @Test func `open image in new tab from the menu adds a background tab`() async throws {
        let image = TestPages.url("image.svg")
        let page = try await showPage("<img src='\(image.absoluteString)' style='display:block;width:800px;height:600px'>", element: "IMG")
        let driver = try await rightClick(choosing: .openImageInNewTab)

        #expect(driver.choices.compactMap(\.self) == [.openImageInNewTab])
        try await waitUntil { manager.tabs.count == 2 }
        #expect(manager.selectedTab === page)
        try await waitUntil { manager.tabs[1].url == image }
    }
}
