import AppKit
import Foundation
@testable import Matcha
import SwiftData
import SwiftUI
import Testing
import WebKit

@MainActor
struct WindowModelTests {
    private let session: BrowserSession
    private let model: WindowModel

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        model = WindowModel(session: session, defaults: nil)
    }

    @Test func `starts on the first space`() {
        #expect(model.space === session.spaces[0])
        #expect(model.spaceIndex == 0)
    }

    @Test func `new space is added to the same profile and shown`() {
        model.newSpace()
        #expect(session.spaces.count == 2)
        #expect(model.space === session.spaces[1])
        #expect(model.space.record.name == String(localized: "Space \(2)"))
        #expect(model.space.record.profile?.id == session.spaces[0].record.profile?.id)
        #expect(model.space.record.symbol != session.spaces[0].record.symbol)
        #expect(model.space.theme != session.spaces[0].theme)
        #expect(model.transitionEdge == .trailing)
    }

    @Test func `locate finds a tab in any space and nil for a missing one`() {
        let first = model.space
        let tab = first.tabManager.newTab()
        model.newSpace()
        let second = model.space
        let other = second.tabManager.newTab()

        let found = model.locate(TabReference(tabID: tab.id, spaceID: first.id))
        #expect(found?.space === first)
        #expect(found?.tab === tab)
        #expect(model.locate(TabReference(tabID: other.id, spaceID: second.id))?.tab === other)
        #expect(model.locate(TabReference(tabID: tab.id, spaceID: second.id)) == nil)
        #expect(model.locate(TabReference(tabID: UUID(), spaceID: first.id)) == nil)
        #expect(model.locate(TabReference(tabID: tab.id, spaceID: UUID())) == nil)
    }

    @Test func `adjacent spaces do not wrap around`() {
        model.newSpace()
        model.newSpace()
        model.selectSpace(at: 0)
        #expect(model.transitionEdge == .leading)
        model.selectAdjacentSpace(.previous)
        #expect(model.spaceIndex == 0)
        model.selectAdjacentSpace(.next)
        model.selectAdjacentSpace(.next)
        model.selectAdjacentSpace(.next)
        #expect(model.spaceIndex == 2)
    }

    @Test func `editing another space shows it with its editor, which a later switch closes`() {
        let first = model.space
        model.newSpace()
        let second = model.space
        // « Changer l'icône… » sur un Space caché : il s'affiche, sa bulle s'ouvre (l'état survit à la barre recréée).
        model.editSpace(first)
        #expect(model.space === first)
        #expect(model.editedSpaceID == first.id)
        // Changer de Space ferme la bulle ; rester sur le même Space ne la ferme pas.
        model.select(first)
        #expect(model.editedSpaceID == first.id)
        model.select(second)
        #expect(model.editedSpaceID == nil)
    }

    @Test func `each space keeps its own tabs but shares favorites`() {
        let first = model.space.tabManager
        let today = first.newTab()
        let favorite = first.newTab()
        first.setPlace(favorite, to: .favorite)

        model.newSpace()
        let second = model.space.tabManager
        #expect(second.favoriteTabs.first === favorite)
        #expect(second.todayTabs.isEmpty)
        #expect(second.tab(withID: today.id) == nil)
        // Les fenêtres ouvertes depuis le favori arrivent désormais dans le Space affiché.
        #expect(favorite.webView?.uiDelegate === second.coordinator)

        second.setPlace(second.newTab(), to: .favorite)
        model.selectSpace(at: 0)
        #expect(first.favoriteTabs.count == 2)
        #expect(first.todayTabs.map(\.id) == [today.id])
    }

    @Test func `deleting the shown space shows its neighbor and the last one stays`() {
        model.newSpace()
        let second = model.space
        model.deleteSpace(second)
        #expect(session.spaces.count == 1)
        #expect(model.space === session.spaces[0])
        model.deleteSpace(model.space)
        #expect(session.spaces.count == 1)
    }

    @Test func `deleted space is removed from the store and saves nothing more`() throws {
        model.newSpace()
        let second = model.space
        let tab = second.tabManager.newTab()
        second.tabManager.setPlace(tab, to: .pinned)
        second.saveNow()
        model.deleteSpace(second)
        second.saveNow()
        let context = session.container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<SpaceRecord>()) == 1)
        #expect(try context.fetch(FetchDescriptor<TabRecord>()).allSatisfy { $0.id != tab.id })
    }

    @Test func `shown space is remembered`() throws {
        let defaults = try #require(UserDefaults(suiteName: "WindowModelTests-\(UUID().uuidString)"))
        let remembering = WindowModel(session: session, defaults: defaults)
        remembering.newSpace()
        let reopened = WindowModel(session: session, defaults: defaults)
        #expect(reopened.space === session.spaces[1])
    }

    @Test func `spaces can be renamed and get another icon`() {
        let space = model.space
        session.renameSpace(space, to: "  Travail ")
        session.renameSpace(space, to: "   ")
        space.setIcon(.symbol("briefcase.fill"))
        #expect(space.record.name == "Travail")
        #expect(space.record.symbol == "briefcase.fill")
        #expect(space.icon == .symbol("briefcase.fill"))
    }

    @Test func `switching space captures every displayed pane`() async throws {
        let tabManager = model.space.tabManager
        let panes = ["un", "deux"].map { name in
            let tab = tabManager.insertTab(configuration: TestPages.configuration(), after: nil, select: true)
            tab.load(TestPages.url(name))
            return (tab, name)
        }
        try await waitUntil { panes.allSatisfy { $0.0.title == $0.1 && !$0.0.isLoading } }
        tabManager.openInSplit(panes[0].0)
        for (tab, _) in panes {
            tab.savedInteractionState = nil
        }
        model.newSpace()
        #expect(panes.allSatisfy { $0.0.savedInteractionState != nil })
    }

    @Test func `moving a split member to another space takes it out of the split`() {
        let source = model.space
        let other = session.addSpace(inProfileOf: source)
        let first = source.tabManager.newTab(url: blankPage("one"))
        let second = source.tabManager.newTab(url: blankPage("two"))
        source.tabManager.openInSplit(first)
        #expect(source.tabManager.displayedTabs.count == 2)

        model.move(first, to: other)
        #expect(source.tabManager.layout.splits.isEmpty)
        #expect(source.tabManager.selectedTab === second)
        #expect(other.tabManager.todayTabs.first === first)
        #expect(other.tabManager.layout.splits.isEmpty)
    }

    @Test func `copying the selected tab url writes the pasteboard and shows the confirmation`() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("WindowModelTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let tabManager = model.space.tabManager
        let first = tabManager.newTab(url: blankPage("one"))
        tabManager.newTab(url: blankPage("two"))
        tabManager.select(first)

        #expect(model.copySelectedTabURL(to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "about:blank?one")
        #expect(pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] == [blankPage("one")])
        #expect(model.copyConfirmation.isVisible)
        #expect(model.copyConfirmation.presentationCount == 1)
    }

    @Test func `without a url nothing is copied or confirmed`() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("WindowModelTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        pasteboard.clearContents()
        pasteboard.setString("avant", forType: .string)

        // Aucun onglet, puis un onglet vide.
        #expect(!model.copySelectedTabURL(to: pasteboard))
        model.space.tabManager.newTab()
        #expect(!model.copySelectedTabURL(to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "avant")
        #expect(!model.copyConfirmation.isVisible)
        #expect(model.copyConfirmation.presentationCount == 0)
    }

    @Test func `copying the url while Peek is open copies the peek`() async throws {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("WindowModelTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        let tabManager = model.space.tabManager
        let source = tabManager.newTab(url: blankPage("source"))
        let peek = try #require(tabManager.openPeek(blankPage("apercu"), from: source))
        try await waitUntil { peek.tab.url != nil }

        #expect(model.copySelectedTabURL(to: pasteboard))
        #expect(pasteboard.string(forType: .string) == "about:blank?apercu")
    }

    // MARK: Aperçu (tâche 4.4)

    @Test func `changing Space closes Peek`() throws {
        let tabManager = model.space.tabManager
        let source = tabManager.newTab(url: blankPage("source"))
        let peek = try #require(tabManager.openPeek(blankPage("apercu"), from: source))
        model.newSpace()
        #expect(tabManager.peek == nil)
        #expect(peek.tab.webView == nil)
        #expect(source.isLoaded)
    }

    @Test func `deleting a Space closes its Peek`() throws {
        model.newSpace()
        let second = model.space
        let source = second.tabManager.newTab(url: blankPage("source"))
        model.selectSpace(at: 0)
        // L'aperçu du Space supprimé est fermé par la suppression elle-même, pas par un changement de Space.
        let peek = try #require(second.tabManager.openPeek(blankPage("apercu"), from: source))
        model.deleteSpace(second)
        #expect(second.tabManager.peek == nil)
        #expect(peek.tab.webView == nil)
    }

    @Test func `copying a link of any tab shows the confirmation`() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("WindowModelTests-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }
        model.copyLink(blankPage("menu"), to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "about:blank?menu")
        #expect(model.copyConfirmation.isVisible)
    }
}
