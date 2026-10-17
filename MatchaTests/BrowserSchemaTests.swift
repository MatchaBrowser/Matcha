import Foundation
@testable import Matcha
import SwiftData
import Testing

@MainActor
struct BrowserSchemaTests {
    /// Règles de CLAUDE.md pour rester compatible CloudKit : pas d'attribut unique, chaque propriété
    /// optionnelle ou avec une valeur par défaut, chaque relation optionnelle avec son inverse.
    @Test func `schema stays compatible with CloudKit`() {
        let schema = Schema(BrowserSchema.models)
        for entity in schema.entities {
            for attribute in entity.attributes {
                #expect(!attribute.isUnique, "\(entity.name).\(attribute.name) est unique")
                #expect(attribute.isOptional || attribute.defaultValue != nil, "\(entity.name).\(attribute.name) sans défaut")
            }
            for relationship in entity.relationships {
                #expect(relationship.isOptional, "\(entity.name).\(relationship.name) obligatoire")
                #expect(relationship.inverseName != nil, "\(entity.name).\(relationship.name) sans inverse")
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

    /// Tâche 5.2 : une base créée avant `SitePermissionRecord` s'ouvre avec le schéma actuel (migration légère, faite
    /// par SwiftData), sans perdre ses données.
    @Test func `a store from before site permissions opens and keeps its data`() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("ancienne.store")
        let oldModels: [any PersistentModel.Type] = [ProfileRecord.self, SpaceRecord.self, FolderRecord.self, TabRecord.self]
        #expect(BrowserSchema.models.count == oldModels.count + 1)

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

    @Test func `archived tabs have no sidebar place`() {
        let tab = TabRecord(place: .today)
        tab.place = nil
        #expect(tab.placeValue == "archived")
        #expect(tab.place == nil)
    }
}
