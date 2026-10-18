import Foundation

/// Événements qui mènent les extensions d'un état des fenêtres et des onglets au suivant (tâche 6.3). Type pur.
///
/// Ordre, pour que WebKit connaisse toujours les onglets et fenêtres qu'on lui nomme :
/// 1. fenêtres ouvertes (WebKit ouvre leurs onglets, `tabs.onCreated` compris) ;
/// 2. onglets ouverts dans une fenêtre déjà connue ;
/// 3. onglets déplacés d'une fenêtre à l'autre, puis réordonnés dans leur fenêtre ;
/// 4. propriétés changées (titre, adresse, chargement, son, épinglé, zoom) ;
/// 5. onglet actif changé (l'ancien est encore ouvert à ce moment), sinon onglets sélectionnés changés ;
/// 6. onglets fermés dans une fenêtre qui reste ouverte ;
/// 7. fenêtres fermées, chacune après ses onglets (`windowIsClosing`) ;
/// 8. fenêtre active, si elle change ou si une fenêtre s'est ouverte (WebKit tient la nouvelle fenêtre pour active).
nonisolated enum ExtensionEventPlanner {
    static func events(from old: ExtensionBrowserState, to new: ExtensionBrowserState) -> [ExtensionEvent] {
        let oldLocations = old.locations()
        let newLocations = new.locations()
        let oldWindowIDs = Set(old.windows.map(\.id))
        let newWindowIDs = Set(new.windows.map(\.id))
        let opened = new.windows.filter { !oldWindowIDs.contains($0.id) }

        var events = opened.map { ExtensionEvent.openWindow($0.id) }
        for window in new.windows where oldWindowIDs.contains(window.id) {
            for id in tabs(of: window, in: newLocations) where oldLocations[id] == nil {
                events.append(.openTab(id))
            }
        }
        events += moves(from: old, to: new, oldLocations: oldLocations, newLocations: newLocations)
        events += changes(from: old, to: new, oldLocations: oldLocations, newLocations: newLocations)
        events += activations(from: old, to: new, oldLocations: oldLocations, newLocations: newLocations)
        for window in old.windows where newWindowIDs.contains(window.id) {
            for id in tabs(of: window, in: oldLocations) where newLocations[id] == nil {
                events.append(.closeTab(id, windowIsClosing: false))
            }
        }
        for window in old.windows where !newWindowIDs.contains(window.id) {
            for id in tabs(of: window, in: oldLocations) where newLocations[id] == nil {
                events.append(.closeTab(id, windowIsClosing: true))
            }
            events.append(.closeWindow(window.id))
        }
        if new.focusedWindowID != old.focusedWindowID || !opened.isEmpty {
            events.append(.focusWindow(new.focusedWindowID))
        }
        return events
    }

    /// Onglets de `window` qui y ont leur place (sans les doublons d'une autre fenêtre).
    private static func tabs(of window: ExtensionBrowserState.Window, in locations: [UUID: ExtensionBrowserState.Location]) -> [UUID] {
        window.tabIDs.filter { locations[$0]?.windowID == window.id }
    }

    /// Changements de fenêtre, puis changements d'ordre dans une même fenêtre : seuls les onglets réellement déplacés
    /// (pas ceux décalés par une ouverture, une fermeture ou le déplacement d'un autre).
    private static func moves(
        from old: ExtensionBrowserState,
        to new: ExtensionBrowserState,
        oldLocations: [UUID: ExtensionBrowserState.Location],
        newLocations: [UUID: ExtensionBrowserState.Location],
    ) -> [ExtensionEvent] {
        var events: [ExtensionEvent] = []
        for window in new.windows {
            for id in tabs(of: window, in: newLocations) {
                if let previous = oldLocations[id], previous.windowID != window.id {
                    events.append(.moveTab(id, fromIndex: previous.index, oldWindowID: previous.windowID))
                }
            }
            guard let previous = old.window(withID: window.id) else {
                continue
            }
            let stayed = { (id: UUID) in oldLocations[id]?.windowID == window.id && newLocations[id]?.windowID == window.id }
            let before = tabs(of: previous, in: oldLocations).filter(stayed)
            let after = tabs(of: window, in: newLocations).filter(stayed)
            let moved = movedElements(from: before, to: after)
            for id in after where moved.contains(id) {
                if let index = oldLocations[id]?.index {
                    events.append(.moveTab(id, fromIndex: index, oldWindowID: window.id))
                }
            }
        }
        return events
    }

    /// Éléments déplacés de `before` à `after` (mêmes éléments, uniques) : ceux que la plus petite différence retire
    /// puis réinsère.
    static func movedElements(from before: [UUID], to after: [UUID]) -> Set<UUID> {
        var moved = Set<UUID>()
        for change in after.difference(from: before).inferringMoves() {
            if case let .insert(_, element, associatedWith) = change, associatedWith != nil {
                moved.insert(element)
            }
        }
        return moved
    }

    private static func changes(
        from old: ExtensionBrowserState,
        to new: ExtensionBrowserState,
        oldLocations: [UUID: ExtensionBrowserState.Location],
        newLocations: [UUID: ExtensionBrowserState.Location],
    ) -> [ExtensionEvent] {
        var events: [ExtensionEvent] = []
        for window in new.windows {
            for id in tabs(of: window, in: newLocations) where oldLocations[id] != nil {
                guard let before = old.tabs[id], let after = new.tabs[id] else {
                    continue
                }
                let changes = ExtensionTabChanges(from: before, to: after)
                if !changes.isEmpty {
                    events.append(.changeTab(id, changes))
                }
            }
        }
        return events
    }

    /// Nouvel onglet actif de chaque fenêtre (WebKit relit alors sa sélection) ; sinon, onglets sélectionnés ajoutés et
    /// retirés (ceux qui restent ouverts), dans l'ordre de la fenêtre.
    private static func activations(
        from old: ExtensionBrowserState,
        to new: ExtensionBrowserState,
        oldLocations: [UUID: ExtensionBrowserState.Location],
        newLocations: [UUID: ExtensionBrowserState.Location],
    ) -> [ExtensionEvent] {
        var events: [ExtensionEvent] = []
        for window in new.windows {
            let previous = old.window(withID: window.id)
            let previousActive = previous?.activeTabID.flatMap { oldLocations[$0] != nil ? $0 : nil }
            if let active = window.activeTabID, newLocations[active]?.windowID == window.id, active != previous?.activeTabID {
                events.append(.activateTab(active, previousTabID: previousActive))
                continue
            }
            guard let previous else {
                continue
            }
            let order = tabs(of: window, in: newLocations)
            let added = window.selectedTabIDs.subtracting(previous.selectedTabIDs)
            let removed = previous.selectedTabIDs.subtracting(window.selectedTabIDs)
            let selected = order.filter(added.contains)
            let deselected = order.filter(removed.contains)
            if !selected.isEmpty {
                events.append(.selectTabs(selected))
            }
            if !deselected.isEmpty {
                events.append(.deselectTabs(deselected))
            }
        }
        return events
    }
}
