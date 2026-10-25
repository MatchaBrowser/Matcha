import Foundation
@testable import Matcha
import Testing

/// Review IU1: a new drawing of the window gives new closures, but the same actions for the menus.
@MainActor
struct WindowActionsTests {
    private let owner = NSObject()

    private func actions(homeURL: URL? = nil, isSidebarVisible: Bool = true, spaceNames: [String] = ["Perso"]) -> WindowActions {
        WindowActions(
            target: WindowActions.Target(model: ObjectIdentifier(owner), window: nil, homeURL: homeURL),
            newTab: {},
            editAddress: {},
            isCommandBarPresented: false,
            closeCommandBar: {},
            toggleSidebar: {},
            isSidebarVisible: isSidebarVisible,
            toggleDownloads: {},
            isDownloadsPanelShown: false,
            copyURL: {},
            goHome: homeURL.map { _ in {} },
            spaceID: nil,
            spaceNames: spaceNames,
            currentSpaceIndex: 0,
            selectSpace: { _ in },
            newSpace: {},
            showTab: { _ in },
            isPrivate: false,
            importFromArc: nil,
        )
    }

    @Test func `new closures alone give the same actions`() throws {
        let drawn = actions()
        let redrawn = actions()
        #expect(drawn == redrawn)
        #expect(actions() != actions(isSidebarVisible: false))
        #expect(actions() != actions(spaceNames: ["Perso", "Travail"]))
        // `goHome` keeps its address: another homepage is another action.
        let home = try #require(URL(string: "https://example.com/"))
        #expect(actions(homeURL: home) != actions(homeURL: URL(string: "https://example.org/")))
    }
}
