import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Icon of a Space changed by the session: written to `SpaceRecord.symbol`, read back at the next launch.
@MainActor
struct SpaceIconTests {
    @Test func `new spaces still get the default symbols in turn`() throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let second = session.addSpace(inProfileOf: session.spaces[0])
        #expect(second.record.symbol == BrowserSession.spaceSymbols[1])
        #expect(second.icon == .symbol(BrowserSession.spaceSymbols[1]))
    }

    @Test func `symbol and emoji are saved in the record`() throws {
        let container = try BrowserSchema.makeContainer(inMemory: true)
        let space = try BrowserSession(container: container).spaces[0]

        space.setIcon(.emoji("🌿"))
        #expect(space.icon == .emoji("🌿"))
        #expect(space.record.symbol == "emoji:🌿")
        #expect(try savedSymbol(of: space, in: container) == "emoji:🌿")

        space.setIcon(.symbol("graduationcap.fill"))
        #expect(space.icon == .symbol("graduationcap.fill"))
        // A symbol is written without a prefix, as before emoji.
        #expect(try savedSymbol(of: space, in: container) == "graduationcap.fill")
    }

    @Test func `invalid icons give the circle`() throws {
        let space = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true)).spaces[0]
        space.setIcon(.emoji(" 🔥 "))
        #expect(space.icon == .emoji("🔥"))
        space.setIcon(.emoji("ab"))
        #expect(space.icon == .symbol(SidebarIcon.defaultSpaceSymbol))
        space.setIcon(.symbol("star.fill"))
        space.setIcon(.symbol("Not A Symbol"))
        #expect(space.icon == .symbol(SidebarIcon.defaultSpaceSymbol))
        space.setIcon(.emoji("🔥"))
        // Emoji field cleared: the default icon, the circle.
        space.setIcon(.default)
        #expect(space.record.symbol == SidebarIcon.defaultSpaceSymbol)
    }

    @Test func `a symbol written before emoji is read as is`() throws {
        let space = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true)).spaces[0]
        space.record.symbol = "moon.fill"
        #expect(space.icon == .symbol("moon.fill"))
    }

    /// Store on disk: the chosen icon comes back at the next launch, through another container.
    @Test func `the icon is back after a relaunch`() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("icones.store")

        let first = try BrowserSession(container: makeContainer(at: url))
        let second = first.addSpace(inProfileOf: first.spaces[0])
        first.spaces[0].setIcon(.emoji("🇫🇷"))
        second.setIcon(.symbol("mountain.2.fill"))
        first.saveAll()

        let relaunched = try BrowserSession(container: makeContainer(at: url))
        #expect(relaunched.spaces.map(\.icon) == [.emoji("🇫🇷"), .symbol("mountain.2.fill")])
    }

    private func makeContainer(at url: URL) throws -> ModelContainer {
        let schema = Schema(BrowserSchema.models)
        return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
    }

    /// The Space's `symbol` as stored, read by another context.
    private func savedSymbol(of space: SpaceSession, in container: ModelContainer) throws -> String? {
        let id = space.id
        return try ModelContext(container).fetch(FetchDescriptor<SpaceRecord>(predicate: #Predicate { $0.id == id })).first?.symbol
    }
}
