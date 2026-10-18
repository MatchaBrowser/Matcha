import Foundation

/// Ce que les extensions voient des fenêtres et des onglets à un instant donné (tâche 6.3). Type pur : deux états
/// successifs sont comparés par `ExtensionEventPlanner`, qui en tire les événements à donner au contrôleur des
/// extensions. Fenêtres et onglets sont désignés par leur identifiant.
nonisolated struct ExtensionBrowserState: Equatable, Sendable {
    /// Une fenêtre : ses onglets dans l'ordre, l'onglet actif (celui au premier plan) et les onglets sélectionnés (les
    /// panneaux du split affiché, l'onglet actif compris).
    struct Window: Equatable, Sendable {
        var id: UUID
        var tabIDs: [UUID]
        var activeTabID: UUID?
        var selectedTabIDs: Set<UUID> = []
    }

    /// Propriétés d'un onglet suivies par les extensions (`tabs.onUpdated`).
    struct Tab: Equatable, Sendable {
        var title: String?
        var url: URL?
        var isLoading = false
        var isPlayingAudio = false
        var isPinned = false
        var zoomFactor = 1.0
    }

    /// Place d'un onglet : sa fenêtre et son rang dans celle-ci.
    struct Location: Equatable, Sendable {
        var windowID: UUID
        var index: Int
    }

    /// Fenêtres, dans l'ordre où elles ont été vues.
    var windows: [Window] = []
    var tabs: [UUID: Tab] = [:]
    /// Fenêtre active (fenêtre clé de l'app) ; nil si aucune fenêtre vue par les extensions ne l'est.
    var focusedWindowID: UUID?

    func window(withID id: UUID) -> Window? {
        windows.first { $0.id == id }
    }

    /// Place de chaque onglet ; un onglet présent deux fois garde la première.
    func locations() -> [UUID: Location] {
        var result: [UUID: Location] = [:]
        for window in windows {
            for (index, id) in window.tabIDs.enumerated() where result[id] == nil {
                result[id] = Location(windowID: window.id, index: index)
            }
        }
        return result
    }
}

/// Propriétés d'un onglet qui ont changé (équivalent pur de `WKWebExtension.TabChangedProperties`).
nonisolated struct ExtensionTabChanges: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let loading = ExtensionTabChanges(rawValue: 1 << 0)
    static let pinned = ExtensionTabChanges(rawValue: 1 << 1)
    static let playingAudio = ExtensionTabChanges(rawValue: 1 << 2)
    static let title = ExtensionTabChanges(rawValue: 1 << 3)
    static let url = ExtensionTabChanges(rawValue: 1 << 4)
    static let zoomFactor = ExtensionTabChanges(rawValue: 1 << 5)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// Ce qui diffère de `old` à `new`.
    init(from old: ExtensionBrowserState.Tab, to new: ExtensionBrowserState.Tab) {
        var changes: ExtensionTabChanges = []
        if old.isLoading != new.isLoading {
            changes.insert(.loading)
        }
        if old.isPinned != new.isPinned {
            changes.insert(.pinned)
        }
        if old.isPlayingAudio != new.isPlayingAudio {
            changes.insert(.playingAudio)
        }
        if old.title != new.title {
            changes.insert(.title)
        }
        if old.url != new.url {
            changes.insert(.url)
        }
        if old.zoomFactor != new.zoomFactor {
            changes.insert(.zoomFactor)
        }
        self = changes
    }
}

/// Un événement à donner au contrôleur des extensions (`WKWebExtensionController.didOpenTab…`).
nonisolated enum ExtensionEvent: Equatable, Sendable {
    /// Fenêtre ouverte ; WebKit ouvre lui-même ses onglets (`didOpenWindow`).
    case openWindow(UUID)
    case openTab(UUID)
    /// Onglet déplacé : depuis le rang `fromIndex` de la fenêtre `oldWindowID` (la même ou une autre).
    case moveTab(UUID, fromIndex: Int, oldWindowID: UUID)
    case changeTab(UUID, ExtensionTabChanges)
    /// Nouvel onglet actif de sa fenêtre ; WebKit relit alors les onglets sélectionnés de la fenêtre.
    case activateTab(UUID, previousTabID: UUID?)
    case selectTabs([UUID])
    case deselectTabs([UUID])
    case closeTab(UUID, windowIsClosing: Bool)
    case closeWindow(UUID)
    case focusWindow(UUID?)
}
