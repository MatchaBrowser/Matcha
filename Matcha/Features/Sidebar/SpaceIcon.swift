import SwiftUI

/// Icon of a Space in the sidebar's buttons (Space switcher, column of icons, review CO4): gray symbol (larger and in
/// the foreground for the displayed Space), or emoji, which keeps its colors and is dimmed for another Space; a circle
/// behind the displayed one. A single `Text` (`SidebarIconView.text`): the editor's popover stays in the accessibility
/// tree when an emoji replaces the symbol.
struct SpaceIcon: View {
    let space: SpaceSession
    let isCurrent: Bool

    var body: some View {
        SidebarIconView.text(
            space.icon,
            defaultSymbol: SidebarIcon.defaultSpaceSymbol,
            tint: isCurrent ? .primary : .secondary,
            size: isCurrent ? 11 : 9,
            emojiSize: isCurrent ? 14 : 12,
        )
        .opacity(isCurrent || space.icon.emoji == nil ? 1 : 0.6)
        .frame(width: 24, height: 24)
        .background(Circle().fill(Color.primary.opacity(isCurrent ? 0.12 : 0)))
        .contentShape(Rectangle())
    }
}
