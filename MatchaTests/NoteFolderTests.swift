import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Folders of the notes library (task 12.1): ranks, moves, cycles, profiles, deletion with their notes.
@MainActor
struct NoteFolderTests {
    private let container: ModelContainer
    private let store: NoteStore
    private let profile = UUID()

    init() throws {
        container = try BrowserSchema.makeContainer(inMemory: true)
        store = NoteStore(context: container.mainContext)
    }

    @Test func `folders are ranked after their siblings`() throws {
        let work = try #require(store.createFolder(named: " Work ", profileID: profile))
        let home = try #require(store.createFolder(named: "Home", profileID: profile))
        let client = try #require(store.createFolder(named: "Client", parentID: work.id, profileID: profile))
        #expect(work.name == "Work")
        #expect(store.folders(ofProfile: profile, parentID: nil).map(\.name) == ["Work", "Home"])
        #expect(store.folders(ofProfile: profile, parentID: work.id).map(\.id) == [client.id])
        #expect(client.order == 0)
        #expect(home.order == work.order + 1)
        #expect(store.folders(ofProfile: UUID(), parentID: nil).isEmpty)
    }

    @Test func `an empty name keeps the old one`() throws {
        let folder = try #require(store.createFolder(named: "Work", profileID: profile))
        store.renameFolder(folder.id, to: "  ")
        #expect(store.folders.first?.name == "Work")
        store.renameFolder(folder.id, to: "Projects")
        #expect(store.folders.first?.name == "Projects")
    }

    @Test func `a folder can't go inside itself`() throws {
        let work = try #require(store.createFolder(named: "Work", profileID: profile))
        let client = try #require(store.createFolder(named: "Client", parentID: work.id, profileID: profile))
        let archive = try #require(store.createFolder(named: "Archive", parentID: client.id, profileID: profile))
        #expect(!store.moveFolder(work.id, toParent: work.id))
        #expect(!store.moveFolder(work.id, toParent: archive.id))

        #expect(store.moveFolder(archive.id, toParent: nil))
        #expect(store.folders(ofProfile: profile, parentID: nil).map(\.name) == ["Work", "Archive"])
        #expect(store.moveFolder(work.id, toParent: archive.id))
        #expect(store.folders(ofProfile: profile, parentID: archive.id).map(\.id) == [work.id])
    }

    @Test func `folders and notes stay within their profile`() throws {
        let other = try #require(store.createFolder(named: "Other", profileID: UUID()))
        let folder = try #require(store.createFolder(named: "Work", profileID: profile))
        #expect(store.createFolder(named: "Inside", parentID: other.id, profileID: profile) == nil)
        #expect(!store.moveFolder(folder.id, toParent: other.id))
        #expect(store.createNote(profileID: profile, folderID: other.id) == nil)

        let note = try #require(store.createNote(profileID: profile))
        store.move(note.id, toFolder: other.id)
        #expect(store.notes.first?.folderID == nil)
        store.move(note.id, toFolder: folder.id)
        #expect(store.notes.first?.folderID == folder.id)
        store.move(note.id, toFolder: nil)
        #expect(store.notes.first?.folderID == nil)
    }

    @Test func `deleting a folder deletes its subfolders and their notes`() throws {
        let work = try #require(store.createFolder(named: "Work", profileID: profile))
        let client = try #require(store.createFolder(named: "Client", parentID: work.id, profileID: profile))
        let home = try #require(store.createFolder(named: "Home", profileID: profile))
        _ = store.createNote(profileID: profile, folderID: work.id)
        _ = store.createNote(profileID: profile, folderID: client.id)
        let kept = try #require(store.createNote(profileID: profile, folderID: home.id))
        let loose = try #require(store.createNote(profileID: profile))

        store.deleteFolder(work.id)
        #expect(store.folders.map(\.id) == [home.id])
        #expect(Set(store.notes.map(\.id)) == [kept.id, loose.id])
        #expect(try container.mainContext.fetchCount(FetchDescriptor<NoteRecord>()) == 2)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<NoteFolderRecord>()) == 1)
    }
}
