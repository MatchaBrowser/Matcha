import SwiftUI

/// A sidebar row (tab, folder, favorite) without the mouse (audit H3): with keyboard navigation on (System Settings >
/// Keyboard), ⇥ reaches it, Space or Return opens it, ⌥⌘↑ and ⌥⌘↓ move it in its list; VoiceOver offers the same moves
/// as actions. A click never gives it keyboard focus: the page keeps it.
struct SidebarRowKeyboard: ViewModifier {
    let activate: () -> Void
    /// Moves one step (−1 up, +1 down); false at the edge of the list.
    let move: (Int) -> Bool
    /// Favorites are tiles side by side: left and right.
    var isHorizontal = false
    /// False while a field of the row is edited (folder name): the keys stay with it.
    var isEnabled = true

    func body(content: Content) -> some View {
        content
            .focusable(isEnabled, interactions: .activate)
            .onKeyPress(keys: [.space, .return]) { press in
                guard isEnabled, press.modifiers.isEmpty else {
                    return .ignored
                }
                activate()
                return .handled
            }
            .onKeyPress(keys: [.upArrow, .downArrow]) { press in
                guard isEnabled, press.modifiers == [.command, .option] else {
                    return .ignored
                }
                return moveStep(press.key == .upArrow ? -1 : 1) ? .handled : .ignored
            }
            .accessibilityAction(named: isHorizontal ? Self.moveLeft : Self.moveUp) { _ = moveStep(-1) }
            .accessibilityAction(named: isHorizontal ? Self.moveRight : Self.moveDown) { _ = moveStep(1) }
    }

    private static let moveUp = Text("Move Up", comment: "VoiceOver action of a sidebar row: moves it one step up")
    private static let moveDown = Text("Move Down", comment: "VoiceOver action of a sidebar row: moves it one step down")
    private static let moveLeft = Text("Move Left", comment: "VoiceOver action of a favorite tile: moves it one step left")
    private static let moveRight = Text("Move Right", comment: "VoiceOver action of a favorite tile: moves it one step right")

    private func moveStep(_ offset: Int) -> Bool {
        withMotion(.easeOut(duration: 0.15)) { move(offset) }
    }
}

extension View {
    /// See `SidebarRowKeyboard`.
    func sidebarRowKeyboard(
        isHorizontal: Bool = false,
        isEnabled: Bool = true,
        activate: @escaping () -> Void,
        move: @escaping (Int) -> Bool,
    ) -> some View {
        modifier(SidebarRowKeyboard(activate: activate, move: move, isHorizontal: isHorizontal, isEnabled: isEnabled))
    }
}
