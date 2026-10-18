import Foundation
import OSLog

/// Prépare les listes de blocage livrées dans un magasin de listes compilées (tâche 6.2). Pour chaque liste du
/// manifeste : la version déjà compilée est relue telle quelle si elle est retenue et toujours dans le magasin ; sinon
/// la liste est compilée (WebKit compile sur sa propre file, la lecture et la découpe se font hors du fil principal).
/// Une liste de plus de `maximumRuleCount` règles est découpée d'avance ; une part que WebKit refuse quand même pour
/// trop de règles fait redécouper la liste en parts deux fois plus petites. Une liste illisible ou refusée pour une
/// autre raison est ignorée (journal), les autres restent. Enfin, nos listes du magasin qui ne servent plus
/// (ancienne version, liste retirée de l'app) en sont supprimées.
@MainActor
struct BlocklistLoader<Store: ContentRuleListStoring> {
    /// Une liste prête : son entrée, ce qui en est retenu et ses listes compilées (une par part).
    struct Loaded {
        let entry: BlocklistEntry
        let record: CompiledBlocklist
        let ruleLists: [Store.RuleList]
        /// Faux si la version déjà compilée a été relue.
        let wasCompiled: Bool
    }

    let store: Store
    /// Règles d'une liste (contenu de son fichier).
    let readRules: (BlocklistEntry) async throws -> Data
    /// Au-delà, une liste est découpée avant d'être donnée à WebKit.
    var maximumRuleCount = RuleListSplitter.webKitMaximumRuleCount
    /// Taille de part en dessous de laquelle on ne redécoupe plus (la liste est alors ignorée).
    var minimumPartSize = 1000
    var now: () -> Date = { .now }

    /// Prépare `entries` (dans l'ordre) à partir de ce qui a été retenu au lancement précédent (`previous`).
    func load(_ entries: [BlocklistEntry], previous: [CompiledBlocklist]) async -> [Loaded] {
        var loaded: [Loaded] = []
        for entry in entries {
            if let record = previous.first(where: { $0.matches(entry) }), let reused = await reuse(record, of: entry) {
                loaded.append(reused)
                continue
            }
            do {
                try await loaded.append(compile(entry))
            } catch {
                let reason = ContentRuleListError.message(of: error)
                Logger.contentBlocker.error(
                    "Liste « \(entry.identifier, privacy: .public) » ignorée : \(reason, privacy: .public)",
                )
            }
        }
        await removeStaleLists(keeping: Set(loaded.flatMap(\.record.storeIdentifiers)))
        return loaded
    }

    /// Relit chaque part de la version compilée ; nil s'il en manque une (elle est alors recompilée).
    private func reuse(_ record: CompiledBlocklist, of entry: BlocklistEntry) async -> Loaded? {
        var lists: [Store.RuleList] = []
        for identifier in record.storeIdentifiers {
            guard let list = await store.lookUp(identifier) else {
                Logger.contentBlocker.notice("Liste « \(entry.identifier, privacy: .public) » absente du magasin : recompilée")
                return nil
            }
            lists.append(list)
        }
        return Loaded(entry: entry, record: record, ruleLists: lists, wasCompiled: false)
    }

    private func compile(_ entry: BlocklistEntry) async throws -> Loaded {
        let rules = try await readRules(entry)
        var size = maximumRuleCount
        while true {
            let split = try await RuleListSplitter.partsInBackground(of: rules, maximumRuleCount: size)
            let identifiers = CompiledBlocklist.storeIdentifiers(for: entry, partCount: split.parts.count)
            do {
                var lists: [Store.RuleList] = []
                for (identifier, part) in zip(identifiers, split.parts) {
                    try await lists.append(store.compile(identifier, rules: part))
                }
                let record = CompiledBlocklist(
                    identifier: entry.identifier,
                    version: entry.version,
                    storeIdentifiers: identifiers,
                    ruleCount: split.ruleCount,
                    compiledAt: now(),
                )
                return Loaded(entry: entry, record: record, ruleLists: lists, wasCompiled: true)
            } catch {
                // Les parts déjà compilées de cet essai ne sont pas gardées : elles partent avec les listes périmées.
                // Moitié arrondie au-dessus : 150 001 règles donnent deux parts, pas trois.
                let current = min(size, split.ruleCount)
                let next = (current + 1) / 2
                guard ContentRuleListError.isTooManyRules(error), next >= minimumPartSize, next < current else {
                    throw error
                }
                Logger.contentBlocker.notice(
                    "Liste « \(entry.identifier, privacy: .public) » trop grosse pour WebKit : parts de \(next, privacy: .public) règles",
                )
                size = next
            }
        }
    }

    private func removeStaleLists(keeping kept: Set<String>) async {
        for identifier in await CompiledBlocklist.staleIdentifiers(available: store.identifiers(), keeping: kept) {
            do {
                try await store.remove(identifier)
            } catch {
                Logger.contentBlocker.notice("Ancienne liste non supprimée du magasin : \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
