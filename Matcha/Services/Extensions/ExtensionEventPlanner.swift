import Foundation

/// Events that take extensions from one state of the windows and tabs to the next (task 6.3). Pure type.
///
/// Order, so that WebKit always knows the tabs and windows it is given:
/// 1. windows opened (WebKit opens their tabs, `tabs.onCreated` included);
/// 2. tabs opened in an already known window;
/// 3. tabs moved from one window to another, then reordered within their window;
/// 4. properties changed (title, address, loading, sound, pinned, zoom);
/// 5. active tab changed (the old one is still open at that point), otherwise selected tabs changed;
/// 6. tabs closed in a window that stays open;
/// 7. windows closed, each one after its tabs (`windowIsClosing`);
/// 8. active window, if it changes or if a window opened (WebKit considers the new window active).
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

    /// Tabs of `window` that belong there (without the duplicates of another window).
    private static func tabs(of window: ExtensionBrowserState.Window, in locations: [UUID: ExtensionBrowserState.Location]) -> [UUID] {
        window.tabIDs.filter { locations[$0]?.windowID == window.id }
    }

    /// Window changes, then order changes within the same window: only the tabs actually moved (not those shifted by an
    /// opening, a closing or the move of another one).
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

    /// Elements moved from `before` to `after` (same elements, unique): those that the smallest difference removes and
    /// then reinserts.
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

    /// New active tab of each window (WebKit then reads its selection again); otherwise, selected tabs added and
    /// removed (those that stay open), in the window's order.
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
