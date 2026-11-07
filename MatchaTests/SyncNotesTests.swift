import Foundation
@testable import Matcha
import Testing

/// Sync of the notes (task 12.8, `SYNC.md` § 2.10): two simulated Macs and an in-memory server. A note and its folder
/// reach the other Mac; the text of a note is never lost in a conflict, it becomes a copy.
@MainActor
struct SyncNotesTests {
    private let server = InMemorySyncServer()

    private struct Pair {
        let macA: SimulatedMac
        let macB: SimulatedMac
        let profile: UUID
    }

    private func pair() async throws -> Pair {
        let macA = SimulatedMac(server: server)
        let macB = SimulatedMac(server: server)
        let profile = macA.addProfile("Personnel")
        try await macA.sync()
        try await macB.sync()
        return Pair(macA: macA, macB: macB, profile: profile)
    }

    private func note(_ title: String, _ text: String, profile: UUID, folder: UUID? = nil) -> SyncNoteFields {
        SyncNoteFields(
            title: title, content: "[\"\(text)\"]", profileId: profile, folderId: folder, link: nil, createdAt: nil, updatedAt: nil,
        )
    }

    private func notes(on mac: SimulatedMac) -> [SyncNoteFields] {
        mac.store.items.values.compactMap { fields in
            if case let .note(note) = fields {
                return note
            }
            return nil
        }
        .sorted { $0.title < $1.title }
    }

    private func edit(_ id: UUID, on mac: SimulatedMac, _ change: (inout SyncNoteFields) -> Void) throws {
        guard case var .note(fields)? = mac.store.items[id] else {
            Issue.record("No note \(id)")
            return
        }
        change(&fields)
        mac.store.items[id] = .note(fields)
    }

    @Test func `a note and its folder reach the other Mac`() async throws {
        let setup = try await pair()
        let folder = UUID()
        setup.macA.store.items[folder] = .noteFolder(SyncNoteFolderFields(name: "Work", order: 0, profileId: setup.profile, parentId: nil))
        let id = UUID()
        setup.macA.store.items[id] = .note(note("Plan", "draft", profile: setup.profile, folder: folder))
        try await setup.macA.sync()
        try await setup.macB.sync()
        #expect(setup.macB.store.items[id] == setup.macA.store.items[id])
        #expect(setup.macB.store.items[folder] != nil)
    }

    @Test func `a newer text from the server keeps this Mac's as a copy`() async throws {
        let setup = try await pair()
        let (macA, macB) = (setup.macA, setup.macB)
        let id = UUID()
        macA.store.items[id] = .note(note("Plan", "v1", profile: setup.profile))
        try await macA.sync()
        try await macB.sync()

        // B writes first but sends last; A's text, newer, wins: B's becomes a copy.
        try edit(id, on: macB) { $0.content = "[\"from B\"]" }
        macA.time = macB.time + 30
        try edit(id, on: macA) { $0.content = "[\"from A\"]" }
        try await macA.sync()
        try await macB.sync()
        try await macB.sync()
        try await macA.sync()

        for mac in [macA, macB] {
            let shown = notes(on: mac)
            #expect(shown.map(\.content) == ["[\"from A\"]", "[\"from B\"]"])
            #expect(shown.map(\.title) == ["Plan", "Plan (conflict)"])
        }
    }

    @Test func `this Mac's newer text wins, the server's becomes a copy`() async throws {
        let setup = try await pair()
        let (macA, macB) = (setup.macA, setup.macB)
        let id = UUID()
        macA.store.items[id] = .note(note("Plan", "v1", profile: setup.profile))
        try await macA.sync()
        try await macB.sync()

        try edit(id, on: macA) { $0.content = "[\"from A\"]" }
        macB.time = macA.time + 30
        try edit(id, on: macB) { $0.content = "[\"from B\"]" }
        try await macA.sync()
        try await macB.sync()
        try await macB.sync()
        try await macA.sync()

        for mac in [macA, macB] {
            #expect(Set(notes(on: mac).map(\.content)) == ["[\"from A\"]", "[\"from B\"]"])
            #expect(mac.store.items[id].flatMap { fields -> String? in
                if case let .note(note) = fields {
                    return note.content
                }
                return nil
            } == "[\"from B\"]")
        }
    }

    @Test func `an edit is kept against a newer deletion`() async throws {
        let setup = try await pair()
        let (macA, macB) = (setup.macA, setup.macB)
        let id = UUID()
        macA.store.items[id] = .note(note("Plan", "v1", profile: setup.profile))
        try await macA.sync()
        try await macB.sync()

        try edit(id, on: macB) { $0.content = "[\"kept\"]" }
        macA.time = macB.time + 30
        macA.store.items[id] = nil
        try await macA.sync()
        try await macB.sync()
        try await macB.sync()
        try await macA.sync()

        for mac in [macA, macB] {
            #expect(mac.store.items[id] == nil)
            #expect(notes(on: mac).map(\.content) == ["[\"kept\"]"])
        }
    }

    @Test func `changes of different fields merge without a copy`() async throws {
        let setup = try await pair()
        let (macA, macB) = (setup.macA, setup.macB)
        let folder = UUID()
        macA.store.items[folder] = .noteFolder(SyncNoteFolderFields(name: "Work", order: 0, profileId: setup.profile, parentId: nil))
        let id = UUID()
        macA.store.items[id] = .note(note("Plan", "v1", profile: setup.profile))
        try await macA.sync()
        try await macB.sync()

        try edit(id, on: macA) { $0.folderId = folder }
        macB.time = macA.time + 30
        try edit(id, on: macB) { $0.content = "[\"from B\"]" }
        try await macA.sync()
        try await macB.sync()
        try await macA.sync()

        for mac in [macA, macB] {
            let shown = notes(on: mac)
            #expect(shown.count == 1)
            #expect(shown.first?.content == "[\"from B\"]")
            #expect(shown.first?.folderId == folder)
        }
    }
}
