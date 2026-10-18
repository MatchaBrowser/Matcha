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

    /// Tâche 5.5 : une base créée avec le schéma de la 5.2 (sans `HistoryRecord`) s'ouvre avec le schéma actuel
    /// (migration légère, faite par SwiftData), sans perdre ses onglets ni ses décisions de permission.
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

        // L'historique s'y écrit et s'y relit.
        let history = HistoryStore(container: container)
        try history.recordVisit(
            url: #require(URL(string: "https://example.com/")),
            title: "Exemple",
            profileID: profileID,
            spaceID: spaces.first?.id,
        )
        let reopened = HistoryStore(container: container)
        await reopened.load()
        #expect(reopened.index(for: profileID)?.entries["example.com"]?.title == "Exemple")
    }

    /// Personnalisation des dossiers : une base créée avec le schéma d'avant (`FolderRecord` sans icône ni couleurs)
    /// s'ouvre avec le schéma actuel (migration légère, faite par SwiftData : trois attributs optionnels ajoutés), sans
    /// rien perdre ; ses dossiers ont l'apparence par défaut, puis enregistrent la leur.
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

        // L'apparence s'y écrit et s'y relit.
        let appearance = FolderAppearance(icon: .symbol("star"), textColor: .white, backgroundColor: ThemeColor(rgb: 0x5856D6))
        layout.setFolderAppearance(childID, appearance)
        store.save(tabs: tabs, layout: layout)
        #expect(folders[childID]?.iconValue == "symbol:star")
        #expect(folders[childID]?.backgroundColorHex == "#5856D6")
        // Relu depuis la base, par un autre contexte.
        let reloaded = try #require(ModelContext(container).fetch(FetchDescriptor<FolderRecord>()).first { $0.id == childID })
        #expect(reloaded.appearance == appearance)
        #expect(reloaded.tabs?.count == 1)
    }

    /// Base créée avec le schéma d'avant la personnalisation des dossiers : un dossier « Travail », son sous-dossier
    /// « Client » replié et un épinglé dedans. Renvoie les identifiants des deux dossiers.
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
