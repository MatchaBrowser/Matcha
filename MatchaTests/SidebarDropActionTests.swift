import Foundation
@testable import Matcha
import Testing

/// What the sidebar accepts (`SidebarDropAction`): two windows on two Spaces of a profile.
@MainActor
struct SidebarDropActionTests {
    private let session: BrowserSession
    private let first: SpaceSession
    private let second: SpaceSession
    private let secondWindow: WindowModel

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        first = try #require(session.spaces.first)
        second = session.addSpace(inProfileOf: first)
        secondWindow = WindowModel(session: session, defaults: nil, spaceID: second.id)
        secondWindow.windowDidAppear()
    }

    private var action: SidebarDropAction {
        SidebarDropAction(tabManager: second.tabManager, windowModel: secondWindow)
    }

    /// Review ON20: refused rather than accepted and ignored, so the item goes back to its place.
    @Test func `a folder of another window, or outside the pinned tabs, is refused`() {
        let folder = first.tabManager.newFolder()
        #expect(!action.perform(.folder(folder), at: .pinned(folder: nil, index: 0)))
        #expect(first.tabManager.layout.pinned.folder(folder) != nil)
        let own = second.tabManager.newFolder()
        #expect(!action.perform(.folder(own), at: .favorites(index: 0)))
        #expect(action.perform(.folder(own), at: .pinned(folder: nil, index: 0)))
    }

    @Test func `a split goes anywhere but the favorites, a tab unknown to the session nowhere`() throws {
        let one = second.tabManager.newTab()
        let two = second.tabManager.newTab()
        let group = try #require(second.tabManager.openInSplit(one, at: 1) ? second.tabManager.layout.split(containing: two.id) : nil)
        #expect(!action.perform(.split(group.id), at: .favorites(index: 0)))
        #expect(!action.perform(.tab(UUID()), at: .today(index: 0)))
    }
}
