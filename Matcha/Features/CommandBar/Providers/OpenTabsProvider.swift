import Foundation

/// Open tabs of all the window's Spaces, the displayed one first. The text is ignored: the ranking does the
/// matching.
///
/// A profile's favorites are shared by its Spaces, but each Space keeps its own copy of them until one switches to
/// it (`adoptFavorites`): those of the displayed profile come only from the displayed Space, those of another
/// profile from the first of its Spaces. A private window has its own session, with a single Space: it sees only
/// its own tabs.
@MainActor
final class OpenTabsProvider: CommandProvider {
    private let windowModel: WindowModel

    init(windowModel: WindowModel) {
        self.windowModel = windowModel
    }

    func candidates(for _: CommandQuery, context _: CommandContext) async -> [CommandCandidate] {
        openTabs()
    }

    /// Favorites, pinned tabs (closed folders included), then today tabs of each Space, without the displayed tab,
    /// without empty tabs and without duplicate identifiers.
    func openTabs() -> [CommandCandidate] {
        let current = windowModel.space
        let spaces = [current] + windowModel.session.spaces.filter { $0 !== current }
        var favoriteProfiles: Set<UUID?> = [current.record.profile?.id]
        var seen: Set<UUID> = []
        var result: [CommandCandidate] = []
        for space in spaces {
            let isCurrent = space === current
            let listsFavorites = isCurrent || favoriteProfiles.insert(space.record.profile?.id).inserted
            result += candidates(in: space, isCurrent: isCurrent, listsFavorites: listsFavorites, seen: &seen)
        }
        return result
    }

    private func candidates(
        in space: SpaceSession,
        isCurrent: Bool,
        listsFavorites: Bool,
        seen: inout Set<UUID>,
    ) -> [CommandCandidate] {
        let tabManager = space.tabManager
        var result: [CommandCandidate] = []
        for tab in tabManager.tabs {
            guard let place = tabManager.place(of: tab),
                  place != .favorite || listsFavorites,
                  !isCurrent || tab.id != tabManager.selectedTabID,
                  // An unloaded pinned tab shows its original address.
                  let url = tab.url ?? tab.pinnedURL,
                  seen.insert(tab.id).inserted
            else {
                continue
            }
            let reference = TabReference(tabID: tab.id, spaceID: space.id)
            result.append(CommandCandidate(
                kind: .tab(reference, place: place, spaceName: isCurrent ? nil : space.record.name, lastActivity: tab.lastActivity),
                title: tab.displayTitle,
                url: url,
            ))
        }
        return result
    }
}
