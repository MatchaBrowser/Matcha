import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Fields of the notes as they travel (task 12.8, `SYNC.md` § 2.9 and § 2.10), the rule of the conflict copies, and
/// Matcha's notes as sync reads and writes them.
@MainActor
@Suite(.webKit)
struct NoteSyncFieldsTests {
    private let profile = UUID()
    private let testDefaults = TestDefaults("NoteSyncFieldsTests")

    private func json(_ text: String) throws -> SyncJSON {
        try JSONDecoder().decode(SyncJSON.self, from: Data(text.utf8))
    }

    // MARK: Fields

    @Test func `a note is read leniently, without its profile or document it is ignored`() throws {
        let link = #"{"url": "https://example.com/a", "key": "example.com/a", "scope": "page", "title": "A"}"#
        let full = try json(
            "{\"title\": \"Plan\", \"content\": \"[]\", \"profileId\": \"\(profile.uuidString)\", \"folderId\": 3, "
                + "\"createdAt\": \"2026-11-04T10:00:00.000Z\", \"link\": \(link)}",
        )
        let fields = try #require(SyncFields(json: full, type: .note))
        guard case let .note(note) = fields else {
            Issue.record("Not a note")
            return
        }
        #expect(note.title == "Plan")
        #expect(note.folderId == nil)
        #expect(note.link?.noteLink?.key == "example.com/a")
        #expect(note.createdAt == SyncCoding.date(from: "2026-11-04T10:00:00.000Z"))
        #expect(note.updatedAt == nil)

        let badLink = try json("""
        {"content": "[]", "profileId": "\(profile.uuidString)", "link": {"url": "ftp://x", "key": "k", "scope": "page"}}
        """)
        guard case let .note(standalone)? = SyncFields(json: badLink, type: .note) else {
            Issue.record("Not a note")
            return
        }
        #expect(standalone.link == nil)
        #expect(standalone.title.isEmpty)

        #expect(try SyncFields(json: json("{\"content\": \"[]\"}"), type: .note) == nil)
        #expect(try SyncFields(json: json("{\"profileId\": \"\(profile.uuidString)\", \"content\": 3}"), type: .note) == nil)
        #expect(try SyncFields(json: json("{\"profileId\": \"\(profile.uuidString)\", \"name\": 3}"), type: .noteFolder) != nil)
    }

    // MARK: Conflict copies

    private func fields(title: String, content: String) throws -> SyncJSON {
        try json("{\"title\": \"\(title)\", \"content\": \"\(content)\", \"profileId\": \"\(profile.uuidString)\"}")
    }

    @Test func `a lost text becomes a copy, a kept one doesn't`() throws {
        let baseline = try fields(title: "Plan", content: "v1")
        let mine = try fields(title: "Plan", content: "mine")
        let theirs = try fields(title: "Plan", content: "theirs")
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let copy = SyncNoteConflict.copy(of: mine, winner: theirs, baseline: baseline, resolution: .replaced, now: now)
        #expect(copy?.content == "mine")
        #expect(copy?.title == "Plan (conflict)")
        #expect(copy?.createdAt == now)
        // Unchanged text, or the same text on both sides: nothing to keep.
        #expect(SyncNoteConflict.copy(of: baseline, winner: theirs, baseline: baseline, resolution: .replaced, now: now) == nil)
        #expect(SyncNoteConflict.copy(of: theirs, winner: theirs, baseline: baseline, resolution: .replaced, now: now) == nil)
        // Merged: lost only if both changed the same field.
        let retitled = try fields(title: "New", content: "v1")
        #expect(SyncNoteConflict.copy(of: mine, winner: retitled, baseline: baseline, resolution: .merged, now: now) == nil)
        #expect(SyncNoteConflict.copy(of: mine, winner: theirs, baseline: baseline, resolution: .merged, now: now) != nil)
        // Against a deletion: any change of the text.
        #expect(SyncNoteConflict.copy(of: mine, winner: nil, baseline: baseline, resolution: .deleted, now: now)?.content == "mine")
        #expect(SyncNoteConflict.copy(of: baseline, winner: nil, baseline: baseline, resolution: .deleted, now: now) == nil)
        // An empty title gets a name.
        let untitled = try fields(title: "", content: "mine")
        #expect(SyncNoteConflict.copy(of: untitled, winner: nil, baseline: baseline, resolution: .deleted, now: now)?
            .title == "Untitled (conflict)")
    }

    // MARK: Matcha's notes

    @Test func `the notes of Matcha travel, a note too large stays here`() throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let store = MatchaSyncStore(session: session, defaults: testDefaults.make(), identifiers: .testAccount)
        let profile = try #require(session.profiles.first?.id)
        #expect(store.hasOnlyFirstLaunchData)
        let folder = try #require(session.notes.createFolder(named: "Work", profileID: profile))
        let note = try #require(session.notes.createNote(profileID: profile, title: "Plan", folderID: folder.id))
        let large = try #require(session.notes.createNote(profileID: profile, title: "Large"))
        session.notes.setContent("[\"" + String(repeating: "a", count: NoteSyncLimit.maximumFieldsBytes) + "\"]", of: large.id)

        let snapshot = try store.snapshot()
        guard case let .note(fields)? = snapshot[note.id] else {
            Issue.record("Note not in the snapshot")
            return
        }
        #expect(fields.folderId == folder.id)
        #expect(snapshot[folder.id] != nil)
        #expect(snapshot[large.id] == nil)
        #expect(try store.exceptions().localRecords.contains(large.id))
        #expect(session.notes.notes.first { $0.id == large.id }?.isTooLargeToSync == true)
        #expect(!store.hasOnlyFirstLaunchData)
    }

    @Test func `received notes are written, a deleted folder leaves its notes at the root`() throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let store = MatchaSyncStore(session: session, defaults: testDefaults.make(), identifiers: .testAccount)
        let profile = try #require(session.profiles.first?.id)
        let folder = UUID()
        let id = UUID()
        let link = try NoteLink(url: #require(URL(string: "https://example.com/a")), scope: .page, title: "A")
        let note = SyncNoteFields(
            title: "Plan",
            content: "[]",
            profileId: profile,
            folderId: folder,
            link: link,
            createdAt: nil,
            updatedAt: nil,
        )

        // Its folder missing: it waits.
        #expect(try store.apply([.upsert(id, .note(note))]) == [id])
        let waiting = try store.apply([
            .upsert(folder, .noteFolder(SyncNoteFolderFields(name: "Work", order: 0, profileId: profile, parentId: nil))),
            .upsert(id, .note(note)),
        ])
        #expect(waiting.isEmpty)
        let summary = try #require(session.notes.notes.first)
        #expect(summary.title == "Plan")
        #expect(summary.folderID == folder)
        #expect(summary.link == link)

        _ = try store.apply([.delete(folder, .noteFolder)])
        #expect(session.notes.notes.first?.folderID == nil)
        _ = try store.apply([.delete(id, .note)])
        #expect(session.notes.notes.isEmpty)
    }
}
