import Foundation
import SwiftData

/// The browser's SwiftData schema and the making of its container.
enum BrowserSchema {
    /// Adding a model is a lightweight migration: SwiftData adds its table and keeps the existing data
    /// (checked by `BrowserSchemaTests`, on a store created with the old schema).
    static let models: [any PersistentModel.Type] = [
        ProfileRecord.self, SpaceRecord.self, FolderRecord.self, TabRecord.self, SitePermissionRecord.self, HistoryRecord.self,
    ]

    /// Local container (sync goes through a server, `SYNC.md`, not CloudKit's mirroring); in memory for tests.
    /// `name` picks the store (`<name>.store` in Application Support), nil for the default store.
    static func makeContainer(inMemory: Bool = false, name: String? = nil) throws -> ModelContainer {
        try makeContainer(configuration(inMemory: inMemory, name: name))
    }

    /// Store at `url` (tests), or named `name` in Application Support, or in memory.
    static func configuration(inMemory: Bool = false, name: String? = nil, url: URL? = nil) -> ModelConfiguration {
        let schema = Schema(models)
        if let url, !inMemory {
            return ModelConfiguration(name, schema: schema, url: url, cloudKitDatabase: .none)
        }
        return ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
    }

    static func makeContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: Schema(models), configurations: configuration)
    }

    /// Puts the files of the store at `url` (`.store`, `-shm`, `-wal`) aside, renamed with the date: an unreadable
    /// store is never deleted (audit R2). Returns the new name of the main file.
    @discardableResult
    static func moveAside(storeAt url: URL, date: Date = .now) throws -> URL {
        let manager = FileManager.default
        let stamp = Int(date.timeIntervalSince1970)
        let aside = url.deletingLastPathComponent().appendingPathComponent("\(url.lastPathComponent).unreadable-\(stamp)")
        for suffix in ["", "-shm", "-wal"] {
            let file = URL(filePath: url.path + suffix)
            if manager.fileExists(atPath: file.path) {
                try manager.moveItem(at: file, to: URL(filePath: aside.path + suffix))
            }
        }
        return aside
    }
}
