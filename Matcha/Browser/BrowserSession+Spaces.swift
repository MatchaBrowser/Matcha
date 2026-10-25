import Foundation
import OSLog
import SwiftData

/// Creating, renaming and deleting Spaces.
extension BrowserSession {
    /// Symbols given in turn to new Spaces; they are the first ones of their icon grid
    /// (`SymbolChoice.spaceIcons`).
    static let spaceSymbols = [
        "circle.fill", "star.fill", "heart.fill", "bolt.fill", "leaf.fill", "moon.fill", "flame.fill", "briefcase.fill", "house.fill",
    ]

    /// Creates a Space in the profile of `anchor` (or of the first Space), with an icon and a preset theme
    /// different from the previous ones, and appends it at the end.
    @discardableResult
    func addSpace(inProfileOf anchor: SpaceSession?) -> SpaceSession {
        addSpace(in: anchor?.record.profile ?? spaces.first?.record.profile)
    }

    /// Creates a Space in `profile`, with an icon and a preset theme different from the previous ones.
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
        return openSpace(record)
    }

    /// Opens the saved Space `record` (already inserted, with its tabs and folders: import, task 7.1) and appends it
    /// at the end.
    @discardableResult
    func openSpace(_ record: SpaceRecord) -> SpaceSession {
        let space = SpaceSession(
            record: record,
            context: container.mainContext,
            websiteDataStore: dataStore(for: record.profile),
            services: services,
            downloadScope: downloadScope,
            sitePermissions: sitePermissions,
            siteZooms: siteZooms,
            history: history,
        )
        appendSpace(space)
        return space
    }

    /// Renames the Space; an empty name keeps the old one.
    func renameSpace(_ space: SpaceSession, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return
        }
        space.record.name = trimmed
        save(container.mainContext)
    }

    /// The window always shows a Space: without any left, the first profile gets its default one (audit R1).
    func ensureOneSpace() {
        guard spaces.isEmpty else {
            return
        }
        let record = SpaceRecord(name: Self.defaultSpaceName, profile: profiles.first)
        container.mainContext.insert(record)
        save(container.mainContext)
        openSpace(record)
        Logger.app.notice("No Space left: default Space created again")
    }

    /// Deletes the Space, its tabs and its folders. The last Space cannot be deleted.
    func deleteSpace(_ space: SpaceSession) {
        guard spaces.count > 1, spaces.contains(where: { $0 === space }) else {
            return
        }
        saveFavoritesBeforeLeaving(space)
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
            Logger.app.error("Spaces not saved: \(error.logSummary, privacy: .public)")
        }
    }
}
