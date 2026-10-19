import Foundation
import OSLog

/// Prepares the shipped blocklists in a store of compiled lists (task 6.2). For each list in the manifest: the
/// already compiled version is looked up as is if it is remembered and still in the store; otherwise the list is
/// compiled (WebKit compiles on its own queue, reading and splitting happen off the main thread). A list with more
/// than `maximumRuleCount` rules is split beforehand; a part that WebKit still refuses for too many rules makes the
/// list be split again into parts half as big. A list that is unreadable or refused for another reason is skipped
/// (log), the others stay. Finally, our lists in the store that are no longer used (old version, list removed from
/// the app) are deleted from it.
@MainActor
struct BlocklistLoader<Store: ContentRuleListStoring> {
    /// A ready list: its entry, what is remembered about it, and its compiled lists (one per part).
    struct Loaded {
        let entry: BlocklistEntry
        let record: CompiledBlocklist
        let ruleLists: [Store.RuleList]
        /// False if the already compiled version was looked up.
        let wasCompiled: Bool
    }

    let store: Store
    /// Rules of a list (contents of its file).
    let readRules: (BlocklistEntry) async throws -> Data
    /// Beyond this, a list is split before being handed to WebKit.
    var maximumRuleCount = RuleListSplitter.webKitMaximumRuleCount
    /// Part size below which the list is no longer split again (the list is then skipped).
    var minimumPartSize = 1000
    var now: () -> Date = { .now }

    /// Prepares `entries` (in order) from what was remembered at the previous launch (`previous`).
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
                    "List “\(entry.identifier, privacy: .public)” ignored: \(reason, privacy: .public)",
                )
            }
        }
        await removeStaleLists(keeping: Set(loaded.flatMap(\.record.storeIdentifiers)))
        return loaded
    }

    /// Looks up each part of the compiled version; nil if one is missing (it is then recompiled).
    private func reuse(_ record: CompiledBlocklist, of entry: BlocklistEntry) async -> Loaded? {
        var lists: [Store.RuleList] = []
        for identifier in record.storeIdentifiers {
            guard let list = await store.lookUp(identifier) else {
                Logger.contentBlocker.notice("List “\(entry.identifier, privacy: .public)” missing from the store: compiled again")
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
                // The parts already compiled in this attempt are not kept: they go away with the stale lists.
                // Half rounded up: 150,001 rules give two parts, not three.
                let current = min(size, split.ruleCount)
                let next = (current + 1) / 2
                guard ContentRuleListError.isTooManyRules(error), next >= minimumPartSize, next < current else {
                    throw error
                }
                Logger.contentBlocker.notice(
                    "List “\(entry.identifier, privacy: .public)” too large for WebKit: parts of \(next, privacy: .public) rules",
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
                Logger.contentBlocker.notice("Old list not removed from the store: \(error.logSummary, privacy: .public)")
            }
        }
    }
}
