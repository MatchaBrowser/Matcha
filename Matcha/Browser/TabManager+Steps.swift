import Foundation

/// Moving a tab one step without dragging (audit H3): VoiceOver actions, ⌥⌘↑ and ⌥⌘↓.
extension TabManager {
    /// Moves the tab one step up (−1) or down (+1) in its list, without dragging (audit H3); false at the edge.
    @discardableResult
    func moveStep(_ tab: BrowserTab, by offset: Int) -> Bool {
        guard let destination = layout.stepDestination(of: tab.id, by: offset) else {
            return false
        }
        move(tab, to: destination)
        return true
    }

    func canMoveStep(_ tab: BrowserTab, by offset: Int) -> Bool {
        layout.stepDestination(of: tab.id, by: offset) != nil
    }
}
