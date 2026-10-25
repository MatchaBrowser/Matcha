import AppKit
import Foundation
import OSLog
import SwiftData

/// Options chosen in the preview of the Arc import (task 7.1).
struct ArcImportOptions: Equatable {
    /// Matcha profile that receives Arc's default profile; nil: the first profile.
    var profileID: UUID?
    /// Arc's open tabs added to the Today tabs of their Space.
    var includesOpenTabs = false
}

/// What an import added.
struct ImportSummary: Equatable {
    var profiles = 0
    var spaces = 0
    var folders = 0
    var tabs = 0
    var favorites = 0
}

/// Imports an Arc sidebar (task 7.1): each Arc Space becomes a new Space (name, icon, colors, pinned tabs and folders,
/// and its open tabs if requested), the profiles added in Arc become profiles, the favorites join those of their
/// profile (without duplicate addresses). The new Spaces are saved with their content, then opened; the favorites of an
/// already open profile join those of its Spaces (`favoritesManager`), which share them.
@MainActor
struct ArcImporter {
    let session: BrowserSession
    /// True if the SF symbol exists on this Mac (replaced in the tests).
    var symbolExists: (String) -> Bool = { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }

    /// Imports `sidebar`; returns the summary and the created Spaces, in order.
    func importSidebar(_ sidebar: ArcSidebar, options: ArcImportOptions) -> (summary: ImportSummary, spaces: [SpaceSession]) {
        let context = session.container.mainContext
        var summary = ImportSummary()
        let target = session.profiles.first { $0.id == options.profileID } ?? session.profiles.first
        let (profiles, created) = resolveProfiles(of: sidebar, defaultProfile: target, context: context)
        summary.profiles = created.count
        // Favorites of the created profiles: saved before their Spaces open, which will read them.
        summary.favorites = insertFavorites(sidebar.favorites, profiles: profiles, only: created, context: context)
        // Spaces: one per Arc Space, and an empty Space for a created profile that has none.
        var records: [SpaceRecord] = []
        for arcSpace in sidebar.spaces {
            let record = insertSpace(named: arcSpace.name, in: profiles[arcSpace.profile] ?? target, at: records.count, context: context)
            if let symbol = ArcAppearance.spaceSymbol(for: arcSpace.icon, symbolExists: symbolExists) {
                record.symbol = symbol
            }
            if let theme = ArcAppearance.theme(for: arcSpace.colors) {
                record.themeData = theme.encoded()
            }
            insert(arcSpace.pinned, in: record, folder: nil, context: context, summary: &summary)
            if options.includesOpenTabs {
                insertOpenTabs(ImportNode.flattenedTabs(of: arcSpace.openTabs), in: record, context: context)
                summary.tabs += ImportNode.tabCount(of: arcSpace.openTabs)
            }
            records.append(record)
        }
        for profile in created where !records.contains(where: { $0.profile === profile }) {
            records.append(insertSpace(named: "", in: profile, at: records.count, context: context))
        }
        session.save(context)
        if !created.isEmpty {
            session.refreshProfiles()
        }
        let opened = records.map(session.openSpace)
        summary.spaces = opened.count
        summary.favorites += importFavorites(sidebar.favorites, profiles: profiles, skipping: created)
        Logger.imports.info(
            "Arc import: \(summary.spaces, privacy: .public) Spaces, \(summary.tabs, privacy: .public) tabs",
        )
        return (summary, opened)
    }

    // MARK: Profiles

    /// Matcha profile for each Arc profile: `defaultProfile` for the default one, the profile with the same name if it
    /// exists (a new import does not duplicate it), otherwise a created profile. Also returns the created profiles.
    private func resolveProfiles(
        of sidebar: ArcSidebar,
        defaultProfile: ProfileRecord?,
        context: ModelContext,
    ) -> (profiles: [ArcSidebar.Profile: ProfileRecord], created: [ProfileRecord]) {
        var profiles: [ArcSidebar.Profile: ProfileRecord] = [:]
        profiles[.default] = defaultProfile
        var created: [ProfileRecord] = []
        let firstOrder = (session.profiles.map(\.order).max() ?? -1) + 1
        for name in sidebar.customProfiles {
            if let existing = session.profiles.first(where: { $0.name == name }) {
                profiles[.custom(name)] = existing
                continue
            }
            let profile = ProfileRecord(name: name, order: firstOrder + created.count)
            context.insert(profile)
            created.append(profile)
            profiles[.custom(name)] = profile
        }
        return (profiles, created)
    }

    // MARK: Records

    /// Favorites of the `only` profiles, saved directly (their Spaces are not open yet). Returns their number.
    private func insertFavorites(
        _ favorites: [ArcSidebar.Profile: [ImportedTab]],
        profiles: [ArcSidebar.Profile: ProfileRecord],
        only created: [ProfileRecord],
        context: ModelContext,
    ) -> Int {
        var count = 0
        for (key, tabs) in favorites {
            guard let profile = profiles[key], created.contains(where: { $0 === profile }) else {
                continue
            }
            for (order, tab) in Self.withoutDuplicates(tabs).enumerated() {
                let record = TabRecord(url: tab.url, title: tab.title, place: .favorite, order: order)
                context.insert(record)
                record.pinnedURL = tab.url
                record.pinnedTitle = tab.title
                record.profile = profile
                record.lastActivity = .distantPast
                count += 1
            }
        }
        return count
    }

    /// Arc's open tabs, among the Today tabs of the Space.
    private func insertOpenTabs(_ tabs: [ImportedTab], in space: SpaceRecord, context: ModelContext) {
        for (order, tab) in tabs.enumerated() {
            let record = TabRecord(url: tab.url, title: tab.title, place: .today, order: order)
            context.insert(record)
            record.space = space
            record.lastActivity = .distantPast
        }
    }

    /// New Space at the end, with the icon and theme a Space added by hand would have (then replaced by Arc's if it has
    /// them); without a name, “Space N”.
    private func insertSpace(named name: String, in profile: ProfileRecord?, at offset: Int, context: ModelContext) -> SpaceRecord {
        let index = session.spaces.count + offset
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = SpaceRecord(
            name: trimmed.isEmpty ? String(localized: "Space \(index + 1)", comment: "Default name of a new Space") : trimmed,
            symbol: BrowserSession.spaceSymbols[index % BrowserSession.spaceSymbols.count],
            order: (session.spaces.map(\.record.order).max() ?? -1) + 1 + offset,
        )
        context.insert(record)
        record.profile = profile
        record.themeData = SpaceTheme.presets[index % SpaceTheme.presets.count].encoded()
        return record
    }

    /// Pinned tabs and folders, in order (tabs and folders of the same container share their index).
    private func insert(
        _ nodes: [ImportNode],
        in space: SpaceRecord,
        folder: FolderRecord?,
        context: ModelContext,
        summary: inout ImportSummary,
    ) {
        for (order, node) in nodes.enumerated() {
            switch node {
            case let .tab(tab):
                let record = TabRecord(url: tab.url, title: tab.title, place: .pinned, order: order)
                context.insert(record)
                record.pinnedURL = tab.url
                record.pinnedTitle = tab.title
                record.space = space
                record.folder = folder
                record.lastActivity = .distantPast
                summary.tabs += 1
            case let .folder(name, children):
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let record = FolderRecord(name: trimmed.isEmpty ? String(localized: "New Folder") : trimmed, order: order)
                context.insert(record)
                record.space = space
                record.parent = folder
                summary.folders += 1
                insert(children, in: space, folder: record, context: context, summary: &summary)
            }
        }
    }

    /// Favorites of the profiles already there: at the end of their favorites, without the addresses already in
    /// favorites. Returns the number of favorites added.
    private func importFavorites(
        _ favorites: [ArcSidebar.Profile: [ImportedTab]],
        profiles: [ArcSidebar.Profile: ProfileRecord],
        skipping created: [ProfileRecord],
    ) -> Int {
        var added = 0
        for (key, tabs) in favorites {
            guard let profile = profiles[key], !created.contains(where: { $0 === profile }),
                  let manager = session.favoritesManager(of: profile.id)
            else {
                continue
            }
            let present = Set(manager.favoriteTabs.compactMap { $0.pinnedURL ?? $0.url })
            let new = Self.withoutDuplicates(tabs).filter { !present.contains($0.url) }
            manager.appendFavorites(new.map { tab in
                StoredTab(
                    id: UUID(),
                    url: tab.url,
                    title: tab.title,
                    pinnedURL: tab.url,
                    pinnedTitle: tab.title,
                    lastActivity: .distantPast,
                    interactionState: nil,
                )
            })
            added += new.count
        }
        return added
    }

    /// Each address only once, in order.
    static func withoutDuplicates(_ tabs: [ImportedTab]) -> [ImportedTab] {
        var seen: Set<URL> = []
        return tabs.filter { seen.insert($0.url).inserted }
    }
}
