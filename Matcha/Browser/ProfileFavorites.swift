import Foundation

/// A profile's favorites, shared by its open Spaces (review ON1): every Space has the same tabs, in the same order,
/// whichever window changes them (`didChange`), and a single Space saves them (`saver`). Their links and the windows
/// they open go to the Space of the window in front (`focus`).
@MainActor
final class ProfileFavorites {
    /// The favorites, in order: the same objects in every Space of the profile.
    private(set) var tabs: [BrowserTab] = []
    private var managers: [WeakTabManager] = []
    /// Space of the window in front, that receives the favorites' links.
    private weak var active: TabManager?
    /// True while a Space's change is passed to the others: their own change is not passed on again.
    private var isPropagating = false

    private var liveManagers: [TabManager] {
        managers.compactMap(\.manager)
    }

    /// The Space that saves the favorites: the first one still open of those that joined.
    var saver: TabManager? {
        liveManagers.first
    }

    /// `manager`, a Space of the profile, shows these favorites from now on. The first one gives the favorites it
    /// restored; the next ones take the same tabs, in place of the copies they restored.
    func join(_ manager: TabManager) {
        guard !liveManagers.contains(where: { $0 === manager }) else {
            return
        }
        let isFirst = liveManagers.isEmpty
        managers = managers.filter { $0.manager != nil } + [WeakTabManager(manager: manager)]
        manager.profileFavorites = self
        if isFirst {
            tabs = manager.favoriteTabs
        } else {
            propagating { manager.adoptFavorites(tabs) }
        }
        route()
    }

    /// `manager`'s Space goes away. Once no Space of the profile is open, the favorites' pages close.
    func leave(_ manager: TabManager) {
        managers = managers.filter { $0.manager != nil && $0.manager !== manager }
        if manager.profileFavorites === self {
            manager.profileFavorites = nil
        }
        if liveManagers.isEmpty {
            tabs.forEach { $0.unload(resettingTo: $0.pinnedURL, title: $0.pinnedTitle) }
            tabs = []
        } else {
            if active === manager {
                active = nil
            }
            route()
        }
    }

    /// The favorites changed in `source` (added, moved, removed, closed): the other Spaces take the same list. A
    /// favorite that left them stays wherever it went in `source`.
    func didChange(in source: TabManager) {
        guard !isPropagating else {
            return
        }
        tabs = source.favoriteTabs
        propagating {
            for manager in liveManagers where manager !== source {
                manager.adoptFavorites(tabs)
            }
        }
        route(fallback: source)
    }

    /// `manager`'s Space is shown by the window in front: the favorites' links open in it.
    func focus(_ manager: TabManager) {
        active = manager
        route()
    }

    private func propagating(_ change: () -> Void) {
        isPropagating = true
        change()
        isPropagating = false
    }

    /// The favorites' web views report to the Space of the window in front, otherwise to `fallback`, otherwise to the
    /// saving Space (each Space registering them took them over).
    private func route(fallback: TabManager? = nil) {
        guard let target = active ?? fallback ?? saver else {
            return
        }
        for tab in tabs where tab.delegate !== target.coordinator {
            tab.delegate = target.coordinator
        }
    }
}
