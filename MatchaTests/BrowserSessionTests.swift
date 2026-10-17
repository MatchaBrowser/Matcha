import Foundation
@testable import Matcha
import SwiftData
import Testing

@MainActor
struct BrowserSessionTests {
    @Test func `first launch creates a default profile and space`() throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        #expect(session.spaces.count == 1)
        #expect(session.spaces.first?.record.name == String(localized: "Home Space", defaultValue: "Home"))
        #expect(session.spaces.first?.record.profile?.name == String(localized: "Personal"))
        #expect(session.spaces.first?.tabManager.tabs.isEmpty == true)
    }

    @Test func `next launch reuses the space and restores its tabs`() async throws {
        let container = try BrowserSchema.makeContainer(inMemory: true)
        let first = BrowserSession(container: container)
        let manager = try #require(first.spaces.first?.tabManager)
        let tab = manager.newTab(url: URL(string: "about:blank"))
        try await waitUntil { tab.url != nil && !tab.isLoading }
        manager.setPlace(tab, to: .pinned)
        first.saveAll()

        let second = BrowserSession(container: container)
        #expect(second.spaces.count == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<ProfileRecord>()) == 1)
        let restored = try #require(second.spaces.first?.tabManager)
        #expect(restored.layout.pinned == [.tab(tab.id)])
        #expect(restored.tab(withID: tab.id)?.url == URL(string: "about:blank"))
    }

    @Test func `s never open the real store`() throws {
        let defaults = try #require(UserDefaults(suiteName: "BrowserSessionTests-\(UUID().uuidString)"))
        let session = BrowserSession.launch(defaults: defaults, environment: ["XCTestConfigurationFilePath": "/tmp/x"])
        let inMemory = session.container.configurations.allSatisfy(\.isStoredInMemoryOnly)
        #expect(inMemory)
    }
}
