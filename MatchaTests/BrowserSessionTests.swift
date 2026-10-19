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
        let first = try BrowserSession(container: container)
        let manager = try #require(first.spaces.first?.tabManager)
        let tab = manager.newTab(url: URL(string: "about:blank"))
        try await waitUntil { tab.url != nil && !tab.isLoading }
        manager.setPlace(tab, to: .pinned)
        first.saveAll()

        let second = try BrowserSession(container: container)
        #expect(second.spaces.count == 1)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<ProfileRecord>()) == 1)
        let restored = try #require(second.spaces.first?.tabManager)
        #expect(restored.layout.pinned == [.tab(tab.id)])
        #expect(restored.tab(withID: tab.id)?.url == URL(string: "about:blank"))
    }

    @Test func `unit tests never open the real store`() throws {
        let defaults = try #require(UserDefaults(suiteName: "BrowserSessionTests-\(UUID().uuidString)"))
        let session = try #require(BrowserSession.launch(
            defaults: defaults,
            environment: ["XCTestConfigurationFilePath": "/tmp/x"],
        ) { _ in .quit })
        let inMemory = session.container.configurations.allSatisfy(\.isStoredInMemoryOnly)
        #expect(inMemory)
    }

    /// Audit R2: an unreadable store is never replaced silently; the user's choice decides, and it is never deleted.
    @Test func `an unreadable store asks the user and is kept aside`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "BrowserSessionTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = folder.appending(path: "matcha.store")
        let garbage = Data("pas une base de données".utf8)
        try garbage.write(to: store)
        let defaults = try #require(UserDefaults(suiteName: "BrowserSessionTests-\(UUID().uuidString)"))
        var asked = 0

        #expect(BrowserSession.launch(defaults: defaults, environment: [:], storeURL: store) { _ in
            asked += 1
            return .quit
        } == nil)
        #expect(try Data(contentsOf: store) == garbage)

        let memory = try #require(BrowserSession.launch(defaults: defaults, environment: [:], storeURL: store) { _ in
            .continueWithoutSaving
        })
        #expect(memory.isInMemory)
        #expect(try Data(contentsOf: store) == garbage)

        let fresh = try #require(BrowserSession.launch(defaults: defaults, environment: [:], storeURL: store) { _ in .startOver })
        #expect(!fresh.isInMemory)
        #expect(fresh.spaces.count == 1)
        let aside = try FileManager.default.contentsOfDirectory(atPath: folder.path).filter { $0.hasPrefix("matcha.store.unreadable-") }
        #expect(aside.count == 1)
        #expect(try Data(contentsOf: folder.appending(path: aside[0])) == garbage)
        #expect(asked == 1)
    }

    /// Audit R3: the default profile and Space are created for an empty store only, once.
    @Test func `the default profile and space are created once`() throws {
        let container = try BrowserSchema.makeContainer(inMemory: true)
        _ = try BrowserSession(container: container)
        _ = try BrowserSession(container: container)
        let context = container.mainContext
        #expect(try context.fetchCount(FetchDescriptor<ProfileRecord>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<SpaceRecord>()) == 1)
    }
}
