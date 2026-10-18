import AppKit
import Foundation
import OSLog
import SwiftData

/// Options choisies dans l'aperçu de l'import d'Arc (tâche 7.1).
struct ArcImportOptions: Equatable {
    /// Profil de Matcha qui reçoit le profil par défaut d'Arc ; nil : le premier profil.
    var profileID: UUID?
    /// Onglets ouverts d'Arc ajoutés aux onglets du jour de leur Space.
    var includesOpenTabs = false
}

/// Ce qu'un import a ajouté.
struct ImportSummary: Equatable {
    var profiles = 0
    var spaces = 0
    var folders = 0
    var tabs = 0
    var favorites = 0
}

/// Importe une barre d'Arc (tâche 7.1) : chaque Space d'Arc devient un nouveau Space (nom, icône, couleurs, épinglés et
/// dossiers, et ses onglets ouverts si on le demande), les profils ajoutés dans Arc deviennent des profils, les favoris
/// rejoignent ceux de leur profil (sans doublon d'adresse). Les nouveaux Spaces sont enregistrés avec leur contenu,
/// puis ouverts ; les favoris d'un profil déjà ouvert passent par le Space qui les tient (`displayedSpace` s'il est de
/// ce profil), puis sont partagés avec les autres Spaces du profil, comme un changement de Space.
@MainActor
struct ArcImporter {
    let session: BrowserSession
    /// Space affiché par la fenêtre qui importe.
    let displayedSpace: SpaceSession?
    /// Vrai si le symbole SF existe sur ce Mac (remplacé dans les tests).
    var symbolExists: (String) -> Bool = { NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil }

    /// Importe `sidebar` ; renvoie le bilan et les Spaces créés, dans l'ordre.
    func importSidebar(_ sidebar: ArcSidebar, options: ArcImportOptions) -> (summary: ImportSummary, spaces: [SpaceSession]) {
        let context = session.container.mainContext
        var summary = ImportSummary()
        let target = session.profiles.first { $0.id == options.profileID } ?? session.profiles.first
        let (profiles, created) = resolveProfiles(of: sidebar, defaultProfile: target, context: context)
        summary.profiles = created.count
        // Favoris des profils créés : enregistrés avant l'ouverture de leurs Spaces, qui les liront.
        summary.favorites = insertFavorites(sidebar.favorites, profiles: profiles, only: created, context: context)
        // Spaces : un par Space d'Arc, et un Space vide pour un profil créé qui n'en a pas.
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
            "Import d'Arc : \(summary.spaces, privacy: .public) Spaces, \(summary.tabs, privacy: .public) onglets",
        )
        return (summary, opened)
    }

    // MARK: Profils

    /// Profil de Matcha de chaque profil d'Arc : `defaultProfile` pour celui par défaut, le profil de même nom s'il
    /// existe (un nouvel import ne le double pas), sinon un profil créé. Renvoie aussi les profils créés.
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

    // MARK: Enregistrements

    /// Favoris des profils `only`, enregistrés directement (leurs Spaces ne sont pas encore ouverts). Renvoie leur nombre.
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

    /// Onglets ouverts d'Arc, parmi les onglets du jour du Space.
    private func insertOpenTabs(_ tabs: [ImportedTab], in space: SpaceRecord, context: ModelContext) {
        for (order, tab) in tabs.enumerated() {
            let record = TabRecord(url: tab.url, title: tab.title, place: .today, order: order)
            context.insert(record)
            record.space = space
            record.lastActivity = .distantPast
        }
    }

    /// Nouveau Space à la fin, avec l'icône et le thème qu'aurait un Space ajouté à la main (remplacés ensuite par ceux
    /// d'Arc s'il en a) ; sans nom, « Space N ».
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

    /// Épinglés et dossiers, dans l'ordre (onglets et dossiers d'un même conteneur partagent leur rang).
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

    /// Favoris des profils déjà là : à la fin de ceux du Space qui les tient, sans les adresses déjà en favori, puis
    /// partagés avec les autres Spaces du profil. Renvoie le nombre de favoris ajoutés.
    private func importFavorites(
        _ favorites: [ArcSidebar.Profile: [ImportedTab]],
        profiles: [ArcSidebar.Profile: ProfileRecord],
        skipping created: [ProfileRecord],
    ) -> Int {
        var added = 0
        for (key, tabs) in favorites {
            guard let profile = profiles[key], !created.contains(where: { $0 === profile }) else {
                continue
            }
            let spaces = session.spaces(of: profile)
            let holder = displayedSpace.flatMap { $0.record.profile?.id == profile.id ? $0 : nil } ?? spaces.first
            guard let holder else {
                continue
            }
            let present = Set(holder.tabManager.favoriteTabs.compactMap { $0.pinnedURL ?? $0.url })
            let new = Self.withoutDuplicates(tabs).filter { !present.contains($0.url) }
            holder.tabManager.appendFavorites(new.map { tab in
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
            for space in spaces where space !== holder {
                space.tabManager.adoptFavorites(from: holder.tabManager)
            }
            added += new.count
        }
        return added
    }

    /// Une seule fois chaque adresse, dans l'ordre.
    static func withoutDuplicates(_ tabs: [ImportedTab]) -> [ImportedTab] {
        var seen: Set<URL> = []
        return tabs.filter { seen.insert($0.url).inserted }
    }
}
