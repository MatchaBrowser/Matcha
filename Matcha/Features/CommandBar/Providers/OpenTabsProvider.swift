import Foundation

/// Open tabs of all the window's Spaces, the displayed one first, and of the windows of their own tabs (detached tabs).
/// The text is ignored: the ranking does the matching.
///
/// A profile's favorites are shared by its Spaces, but each Space keeps its own copy of them until one switches to
/// it (`adoptFavorites`): those of the displayed profile come only from the displayed Space, those of another
/// profile from the first of its Spaces. A private window has its own session, with a single Space: it sees only
/// its own tabs. A window of its own tabs lists them first, then the tabs of every Space.
@MainActor
final class OpenTabsProvider: CommandProvider {
    private let windowModel: WindowModel

    init(windowModel: WindowModel) {
        self.windowModel = windowModel
    }

    func candidates(for _: CommandQuery, context _: CommandContext) async -> [CommandCandidate] {
        openTabs()
    }

    /// Tabs of this window of its own tabs, favorites, pinned tabs (closed folders included) and today tabs of each
    /// Space, then tabs of the other windows of their own tabs; without the displayed tab, without empty tabs and
    /// without duplicate identifiers.
    func openTabs() -> [CommandCandidate] {
        let ownTabs = windowModel.windowTabs
        // A window of its own tabs displays no Space: all of them carry their name.
        let current = ownTabs == nil ? windowModel.space : nil
        let spaces = (current.map { [$0] } ?? []) + windowModel.session.spaces.filter { $0 !== current }
        var favoriteProfiles: Set<UUID?> = current.map { [$0.record.profile?.id] } ?? []
        var seen: Set<UUID> = []
        var result: [CommandCandidate] = []
        if let ownTabs {
            result += candidates(in: ownTabs, label: nil, seen: &seen)
        }
        for space in spaces {
            let isCurrent = space === current
            let listsFavorites = isCurrent || favoriteProfiles.insert(space.record.profile?.id).inserted
            result += candidates(in: space, isCurrent: isCurrent, listsFavorites: listsFavorites, seen: &seen)
        }
        let otherWindow = String(
            localized: "Other Window",
            comment: "Command bar: label of a tab open in another window, outside any Space",
        )
        for tabs in windowModel.session.windowTabs where tabs !== ownTabs {
            result += candidates(in: tabs, label: otherWindow, seen: &seen)
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
                  !isCurrent || tab.id != windowModel.selectedTab?.id,
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

    /// Tabs of a window of its own tabs, referenced by its identifier; `label`: nil for this window's own.
    private func candidates(in tabs: WindowTabs, label: String?, seen: inout Set<UUID>) -> [CommandCandidate] {
        tabs.tabManager.tabs.compactMap { tab in
            guard label != nil || tab.id != windowModel.selectedTab?.id, let url = tab.url, seen.insert(tab.id).inserted else {
                return nil
            }
            return CommandCandidate(
                kind: .tab(TabReference(tabID: tab.id, spaceID: tabs.id), place: .today, spaceName: label, lastActivity: tab.lastActivity),
                title: tab.displayTitle,
                url: url,
            )
        }
    }
}
