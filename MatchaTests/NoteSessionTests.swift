import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Notes in a browser session (task 12.1): none in a private window, deleted with their profile, and a store from
/// before notes opens with its data.
@MainActor
@Suite(.webKit)
struct NoteSessionTests {
    @Test func `a private window makes no notes`() {
        let session = BrowserSession.makePrivate()
        #expect(!session.notes.isPersistent)
        #expect(session.notes.createNote(profileID: session.profiles.first?.id) == nil)
    }

    @Test func `deleting a profile deletes its notes`() async throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let first = try #require(session.profiles.first?.id)
        session.addProfile(named: "Work")
        let profile = try #require(session.profiles.last)
        _ = session.notes.createNote(profileID: first, title: "Kept")
        let folder = try #require(session.notes.createFolder(named: "Projects", profileID: profile.id))
        _ = session.notes.createNote(profileID: profile.id, folderID: folder.id)

        await session.deleteProfile(profile)
        #expect(session.notes.notes.map(\.title) == ["Kept"])
        #expect(session.notes.folders.isEmpty)
        #expect(try session.container.mainContext.fetchCount(FetchDescriptor<NoteRecord>()) == 1)
    }

    /// A store created before notes (without `NoteFolderRecord` and `NoteRecord`) opens with the current schema
    /// (lightweight migration, done by SwiftData: two tables added), without losing anything; notes are written to it.
    @Test func `a store from before notes opens and keeps its data`() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("avant-notes.store")
        let oldModels: [any PersistentModel.Type] = [
            ProfileRecord.self, SpaceRecord.self, FolderRecord.self, TabRecord.self, SitePermissionRecord.self, HistoryRecord.self,
        ]
        #expect(BrowserSchema.models.count == oldModels.count + 2)

        let profileID = try {
            let schema = Schema(oldModels)
            let container = try ModelContainer(
                for: schema,
                configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
            )
            let profile = ProfileRecord(name: "Personnel")
            let space = SpaceRecord(name: "Perso", profile: profile)
            let pinned = TabRecord(url: URL(string: "https://example.com"), title: "Exemple", place: .pinned)
            pinned.space = space
            container.mainContext.insert(profile)
            try container.mainContext.save()
            return profile.id
        }()

        let schema = Schema(BrowserSchema.models)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let context = container.mainContext
        let spaces = try context.fetch(FetchDescriptor<SpaceRecord>())
        #expect(spaces.map(\.name) == ["Perso"])
        #expect(spaces.first?.tabs?.first?.title == "Exemple")
        let store = NoteStore(context: context)
        #expect(store.notes.isEmpty)

        let folder = try #require(store.createFolder(named: "Travail", profileID: profileID))
        let note = try #require(store.createNote(profileID: profileID, title: "Plan", folderID: folder.id))
        let reopened = NoteStore(context: ModelContext(container))
        #expect(reopened.notes.map(\.id) == [note.id])
        #expect(reopened.notes.first?.folderID == folder.id)
    }
}
