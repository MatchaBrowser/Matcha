import Foundation
import SwiftData

/// The browser's SwiftData schema and the making of its container.
enum BrowserSchema {
    /// Adding a model is a lightweight migration: SwiftData adds its table and keeps the existing data
    /// (checked by `BrowserSchemaTests`, on a store created with the old schema).
    static let models: [any PersistentModel.Type] = [
        ProfileRecord.self, SpaceRecord.self, FolderRecord.self, TabRecord.self, SitePermissionRecord.self, HistoryRecord.self,
    ]

    /// Local container (iCloud sync will come in phase 7); in memory for tests.
    /// `name` picks the store (`<name>.store` in Application Support), nil for the default store.
    static func makeContainer(inMemory: Bool = false, name: String? = nil) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
