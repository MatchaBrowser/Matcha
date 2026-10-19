import Foundation
@testable import Matcha
import SwiftData
import Testing

/// The two ways of each synced record (audit C6): fields written into a new record come out unchanged.
@MainActor
struct SyncRecordFieldsTests {
    private let context: ModelContext

    init() throws {
        context = try ModelContext(BrowserSchema.makeContainer(inMemory: true))
    }

    private func inserted<Model: PersistentModel>(_ model: Model) -> Model {
        context.insert(model)
        return model
    }

    @Test func `profiles, spaces and folders keep their fields`() {
        let profile = inserted(ProfileRecord(name: "Ancien"))
        let profileFields = SyncProfileFields(name: "Travail", order: 3)
        profile.apply(profileFields)
        #expect(profile.syncFields == profileFields)

        let space = inserted(SpaceRecord(name: "Ancien"))
        let spaceFields = SyncSpaceFields(name: "Projets", symbol: "star.fill", theme: .ocean, order: 2, profileId: profile.id)
        space.apply(spaceFields, profile: profile)
        #expect(space.syncFields == spaceFields)

        let parent = inserted(FolderRecord(name: "Parent"))
        parent.apply(SyncFolderFields(name: "Parent", order: 0, isCollapsed: false, spaceId: space.id), space: space, parent: nil)
        let folder = inserted(FolderRecord(name: "Ancien"))
        let folderFields = SyncFolderFields(
            name: "Lectures",
            order: 1,
            isCollapsed: true,
            spaceId: space.id,
            parentId: parent.id,
            icon: "symbol:book",
            textColor: "#FF3B30",
            backgroundColor: "#0A84FF",
        )
        folder.apply(folderFields, space: space, parent: parent)
        #expect(folder.syncFields == folderFields)
    }

    @Test func `tabs keep their fields in each place`() throws {
        let profile = inserted(ProfileRecord(name: "Perso"))
        let space = inserted(SpaceRecord(name: "Maison", profile: profile))
        let folder = inserted(FolderRecord(name: "Dossier"))
        folder.apply(SyncFolderFields(name: "Dossier", order: 0, isCollapsed: false, spaceId: space.id), space: space, parent: nil)
        let url = try #require(URL(string: "https://example.com/page"))
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let favorite = SyncTabFields(place: .favorite, url: url, title: "Favori", order: 0, profileId: profile.id)
        let pinned = SyncTabFields(place: .pinned, url: url, title: "Épinglé", order: 1, spaceId: space.id, folderId: folder.id)
        let today = SyncTabFields(place: .today, url: url, title: "Du jour", order: 2, spaceId: space.id, lastActivity: date)
        for fields in [favorite, pinned, today] {
            let tab = inserted(TabRecord())
            tab.apply(
                fields,
                isNew: true,
                folder: fields.folderId == nil ? nil : folder,
                profile: fields.place == .favorite ? profile : nil,
                space: fields.place == .favorite ? nil : space,
            )
            #expect(tab.syncFields == fields, "\(fields.place)")
        }
    }

    @Test func `a pinned tab that left its origin keeps its page`() throws {
        let space = inserted(SpaceRecord(name: "Maison"))
        let origin = try #require(URL(string: "https://example.com/"))
        let elsewhere = try #require(URL(string: "https://example.com/ailleurs"))
        let moved = try #require(URL(string: "https://example.org/"))
        let tab = inserted(TabRecord(url: elsewhere, place: .pinned))
        tab.pinnedURL = origin
        tab.apply(
            SyncTabFields(place: .pinned, url: moved, title: nil, order: 0, spaceId: space.id),
            isNew: false,
            folder: nil,
            profile: nil,
            space: space,
        )
        #expect(tab.pinnedURL == moved)
        #expect(tab.url == elsewhere)
    }
}
