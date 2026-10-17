import Foundation
import SwiftData

/// Schéma SwiftData du navigateur et fabrication de son conteneur.
enum BrowserSchema {
    /// Ajouter un modèle est une migration légère : SwiftData ajoute sa table et garde les données existantes
    /// (vérifié par `BrowserSchemaTests`, sur une base créée avec l'ancien schéma).
    static let models: [any PersistentModel.Type] = [
        ProfileRecord.self, SpaceRecord.self, FolderRecord.self, TabRecord.self, SitePermissionRecord.self,
    ]

    /// Conteneur local (la synchronisation iCloud viendra en phase 7) ; en mémoire pour les tests.
    /// `name` choisit la base (`<name>.store` dans Application Support), nil pour la base par défaut.
    static func makeContainer(inMemory: Bool = false, name: String? = nil) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(name, schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }
}
