import Foundation

nonisolated extension SidebarLayout {
    /// Moving a tab one step up (`offset` −1) or down (+1) in its own list, without dragging (audit H3: VoiceOver
    /// actions, ⌥⌘↑ and ⌥⌘↓ on a row that has keyboard focus); nil at the edge of the list.
    func stepDestination(of id: UUID, by offset: Int) -> SidebarDestination? {
        guard let (container, index) = container(of: id) else {
            return nil
        }
        let target = index + offset
        guard target >= 0, target < itemCount(in: container) else {
            return nil
        }
        // The rank is read before the move: one step down is “before the item after the next one”.
        return container.destination(at: offset > 0 ? target + 1 : target)
    }

    private func itemCount(in container: Container) -> Int {
        switch container {
        case .favorites: favorites.count
        case .today: today.count
        case .pinned(folder: nil): pinned.count
        case let .pinned(folder?): pinned.folder(folder)?.items.count ?? 0
        }
    }
}
