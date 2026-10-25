import Foundation
@testable import Matcha
import SwiftData
import Testing

@MainActor
struct BrowserSchemaTests {
    /// Rules from CLAUDE.md to stay compatible with CloudKit: no unique attribute, every property optional or with
    /// a default value, every relationship optional with its inverse.
    @Test func `schema stays compatible with CloudKit`() {
        let schema = Schema(BrowserSchema.models)
        for entity in schema.entities {
            for attribute in entity.attributes {
                #expect(!attribute.isUnique, "\(entity.name).\(attribute.name) is unique")
                #expect(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name).\(attribute.name) without a default")
            }
            for relationship in entity.relationships {
                #expect(relationship.isOptional, "\(entity.name).\(relationship.name) obligatoire")
                #expect(relationship.inverseName != nil, "\(entity.name).\(relationship.name) without an inverse")
            }
        }
    }

    @Test func `records keep their relationships`() throws {
        let container = try BrowserSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        let profile = ProfileRecord(name: "Personnel")
        let space = SpaceRecord(name: "Perso", profile: profile)
        let folder = FolderRecord(name: "Travail")
        folder.space = space
        let pinned = TabRecord(url: URL(string: "https://example.com"), title: "Exemple", place: .pinned)
        pinned.space = space
        pinned.folder = folder
        let favorite = TabRecord(url: URL(string: "https://apple.com"), place: .favorite)
        favorite.profile = profile
        context.insert(profile)
        try context.save()

        let spaces = try context.fetch(FetchDescriptor<SpaceRecord>())
        #expect(spaces.count == 1)
        #expect(spaces.first?.profile?.name == "Personnel")
        #expect(spaces.first?.tabs?.count == 1)
        #expect(folder.tabs?.first?.id == pinned.id)
        #expect(profile.favorites?.first?.place == .favorite)
        #expect(pinned.place == .pinned)
    }

    @Test func `deleting a space deletes its tabs and folders`() throws {
        let container = try BrowserSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        let space = SpaceRecord(name: "Perso")
        let tab = TabRecord(place: .today)
        tab.space = space
        let folder = FolderRecord(name: "Dossier")
        folder.space = space
        context.insert(space)
        try context.save()

        context.delete(space)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<TabRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<FolderRecord>()) == 0)
    }

    /// Task 5.2: a store created before `SitePermissionRecord` opens with the current schema (lightweight migration,
    /// done by SwiftData), without losing its data.
    @Test func `a store from before site permissions opens and keeps its data`() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ancienne.store")
        let oldModels: [any PersistentModel.Type] = [ProfileRecord.self, SpaceRecord.self, FolderRecord.self, TabRecord.self]
        #expect(BrowserSchema.models.count > oldModels.count)

        try {
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
        }()

        let schema = Schema(BrowserSchema.models)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let context = container.mainContext
        let spaces = try context.fetch(FetchDescriptor<SpaceRecord>())
        #expect(spaces.map(\.name) == ["Perso"])
        #expect(spaces.first?.profile?.name == "Personnel")
        #expect(spaces.first?.tabs?.first?.title == "Exemple")
        let profileID = spaces.first?.profile?.id
        context.insert(SitePermissionRecord(profileID: profileID, originKey: "https://meet.example.com", kind: .camera, decision: .allow))
        try context.save()
        #expect(SitePermissionStore(context: context).decision(.camera, for: TestOrigins.meet, profileID: profileID) == .allow)
    }

    /// Task 5.5: a store created with the 5.2 schema (without `HistoryRecord`) opens with the current schema
    /// (lightweight migration, done by SwiftData), without losing its tabs or its permission decisions.
    @Test func `a store from before history opens and keeps its data`() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("avant-historique.store")
        let oldModels: [any PersistentModel.Type] = [
            ProfileRecord.self, SpaceRecord.self, FolderRecord.self, TabRecord.self, SitePermissionRecord.self,
        ]
        #expect(BrowserSchema.models.count == oldModels.count + 1)

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
            container.mainContext.insert(SitePermissionRecord(
                profileID: profile.id, originKey: "https://meet.example.com", kind: .camera, decision: .allow,
            ))
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
        #expect(SitePermissionStore(context: context).decision(.camera, for: TestOrigins.meet, profileID: profileID) == .allow)
        #expect(try context.fetchCount(FetchDescriptor<HistoryRecord>()) == 0)

        // History is written to it and read back.
        let history = HistoryStore(container: container)
        try history.recordVisit(
            url: #require(URL(string: "https://example.com/")),
            title: "Exemple",
            profileID: profileID,
            spaceID: spaces.first?.id,
        )
        let reopened = HistoryStore(container: container)
        await reopened.load()
        #expect(reopened.index(for: profileID)?.entriesByKey["example.com"]?.title == "Exemple")
    }

    /// Folder customization: a store created with the previous schema (`FolderRecord` without icon or colors)
    /// opens with the current schema (lightweight migration, done by SwiftData: three optional attributes added),
    /// without losing anything; its folders have the default appearance, then save their own.
    @Test func `a store from before folder appearances opens and keeps its folders`() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("avant-apparence.store")
        #expect(SchemaBeforeFolderAppearance.models.count == BrowserSchema.models.count)

        let (folderID, childID) = try makeStoreBeforeFolderAppearances(at: url)

        let schema = Schema(BrowserSchema.models)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let context = container.mainContext
        let space = try #require(context.fetch(FetchDescriptor<SpaceRecord>()).first)
        let folders = Dictionary(uniqueKeysWithValues: (space.folders ?? []).map { ($0.id, $0) })
        #expect(folders[folderID]?.name == "Travail")
        #expect(folders[childID]?.parent?.id == folderID)
        #expect(folders[childID]?.isCollapsed == true)
        #expect(folders[childID]?.tabs?.first?.title == "Exemple")
        #expect(folders[childID]?.iconValue == nil)
        #expect(folders[childID]?.textColorHex == nil)
        #expect(folders[childID]?.backgroundColorHex == nil)
        let store = SpaceStore(space: space, context: context)
        let (tabs, loadedLayout) = store.load()
        var layout = loadedLayout
        #expect(tabs.map(\.title) == ["Exemple"])
        #expect(layout.pinned.folder(childID)?.appearance == .default)
        #expect(layout.pinned.folder(childID)?.items.count == 1)

        // The appearance is written to it and read back.
        let appearance = FolderAppearance(icon: .symbol("star"), textColor: .white, backgroundColor: ThemeColor(rgb: 0x5856D6))
        layout.setFolderAppearance(childID, appearance)
        store.save(tabs: tabs, layout: layout)
        #expect(folders[childID]?.iconValue == "symbol:star")
        #expect(folders[childID]?.backgroundColorHex == "#5856D6")
        // Read back from the store, through another context.
        let reloaded = try #require(ModelContext(container).fetch(FetchDescriptor<FolderRecord>()).first { $0.id == childID })
        #expect(reloaded.appearance == appearance)
        #expect(reloaded.tabs?.count == 1)
    }

    /// Store created with the schema from before folder customization: a “Travail” folder, its collapsed “Client”
    /// subfolder and a pinned tab inside it. Returns the identifiers of both folders.
    private func makeStoreBeforeFolderAppearances(at url: URL) throws -> (folder: UUID, child: UUID) {
        typealias Old = SchemaBeforeFolderAppearance
        let schema = Schema(Old.models)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none),
        )
        let profile = Old.ProfileRecord(name: "Personnel")
        let space = Old.SpaceRecord(name: "Perso", profile: profile)
        let folder = Old.FolderRecord(name: "Travail", order: 1, isCollapsed: false)
        folder.space = space
        let child = Old.FolderRecord(name: "Client", order: 0, isCollapsed: true)
        child.space = space
        child.parent = folder
        let pinned = Old.TabRecord(url: URL(string: "https://example.com"), title: "Exemple", placeValue: "pinned")
        pinned.space = space
        pinned.folder = child
        container.mainContext.insert(profile)
        try container.mainContext.save()
        return (folder.id, child.id)
    }

    @Test func `archived tabs have no sidebar place`() {
        let tab = TabRecord(place: .today)
        tab.place = nil
        #expect(tab.placeValue == "archived")
        #expect(tab.place == nil)
    }
}
