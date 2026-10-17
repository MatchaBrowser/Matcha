import Foundation
import OSLog
import SwiftData

/// Création, renommage et suppression des Spaces.
extension BrowserSession {
    /// Symboles proposés pour l'icône d'un Space.
    static let spaceSymbols = [
        "circle.fill", "star.fill", "heart.fill", "bolt.fill", "leaf.fill", "moon.fill", "flame.fill", "briefcase.fill", "house.fill",
    ]

    /// Crée un Space dans le profil de `anchor` (ou du premier Space), avec une icône et un thème
    /// prédéfini différents des précédents, et l'ajoute à la fin.
    @discardableResult
    func addSpace(inProfileOf anchor: SpaceSession?) -> SpaceSession {
        addSpace(in: anchor?.record.profile ?? spaces.first?.record.profile)
    }

    /// Crée un Space dans `profile`, avec une icône et un thème prédéfini différents des précédents.
    @discardableResult
    func addSpace(in profile: ProfileRecord?) -> SpaceSession {
        let context = container.mainContext
        let index = spaces.count
        let record = SpaceRecord(
            name: String(localized: "Space \(index + 1)", comment: "Default name of a new Space"),
            symbol: Self.spaceSymbols[index % Self.spaceSymbols.count],
            order: (spaces.map(\.record.order).max() ?? -1) + 1,
            profile: profile,
        )
        record.themeData = SpaceTheme.presets[index % SpaceTheme.presets.count].encoded()
        context.insert(record)
        save(context)
        let space = SpaceSession(
            record: record,
            context: context,
            websiteDataStore: dataStore(for: profile),
            faviconService: faviconService,
            downloadScope: downloadScope,
            sitePermissions: sitePermissions,
        )
        appendSpace(space)
        return space
    }

    /// Renomme le Space ; un nom vide garde l'ancien.
    func renameSpace(_ space: SpaceSession, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        space.record.name = trimmed
        save(container.mainContext)
    }

    func setSymbol(_ symbol: String, of space: SpaceSession) {
        space.record.symbol = symbol
        save(container.mainContext)
    }

    /// Supprime le Space, ses onglets et ses dossiers. Le dernier Space ne peut pas être supprimé.
    func deleteSpace(_ space: SpaceSession) {
        guard spaces.count > 1, spaces.contains(where: { $0 === space }) else {
            return
        }
        space.close()
        removeSpace(space)
        let context = container.mainContext
        context.delete(space.record)
        save(context)
    }

    func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            Logger.app.error("Spaces non enregistrés : \(error.localizedDescription, privacy: .public)")
        }
    }
}
