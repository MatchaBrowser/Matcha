import SwiftUI

extension View {
    /// What a tab of the sidebar offers without the mouse, the same for a row, a favorite tile, an icon of the column
    /// and a pane of a split (review CO4): one element named by its title, selected or not, that VoiceOver opens (and
    /// closes, with `canClose`), reached with ⇥ and moved by `move` (`SidebarRowKeyboard`), with its sound. While its
    /// name is edited (`isEditing`), the field is reachable and keeps the keys.
    func tabAccessibility(
        _ tab: BrowserTab,
        tabManager: TabManager,
        isSelected: Bool,
        canClose: Bool = false,
        isHorizontal: Bool = false,
        isEditing: Bool = false,
        move: @escaping (Int) -> Bool,
    ) -> some View {
        accessibilityElement(children: isEditing ? .contain : .ignore)
            .accessibilityLabel(Text(verbatim: tab.displayTitle))
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { TabActivation.activate(tab, in: tabManager) }
            .accessibilityActions {
                if canClose {
                    Button("Close Tab") { tabManager.close(tab) }
                }
            }
            .sidebarRowKeyboard(isHorizontal: isHorizontal, isEnabled: !isEditing) {
                TabActivation.activate(tab, in: tabManager)
            } move: { move($0) }
            // “Playing Audio”; in Debug, “suspended” for a sleeping tab (UI tests of task 5.6).
            .tabAudioAccessibility(tab)
    }
}
