import SwiftUI

/// Editor of a Space, in the popover opened by a click on the displayed Space's icon, or by “Change Icon…” and
/// “Edit Theme…” in its menu: its name, its icon (SF Symbols or an emoji), then its theme. Each choice applies
/// right away to the Space and is saved.
struct SpaceEditor: View {
    let space: SpaceSession
    /// Esc in the emoji field: closes the popover (elsewhere, the popover closes by itself).
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: space.record.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)
            SpaceIconPicker(space: space, close: close)
            Divider()
            SpaceThemeEditor(theme: Binding { space.theme } set: { space.setTheme($0) })
        }
        .padding(16)
        .frame(width: 300)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("spaceEditor")
    }
}

/// Icon of a Space, a section of its editor: grid of symbols (the Space's own is circled), then the emoji. Emptying
/// the emoji field restores the circle, the default icon.
private struct SpaceIconPicker: View {
    let space: SpaceSession
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SpaceEditorSectionTitle(Text("Icon"))
            SymbolPickerGrid(
                symbols: SymbolChoice.spaceIcons,
                selection: space.icon.selectedSymbol(defaultSymbol: SidebarIcon.defaultSpaceSymbol),
                identifierPrefix: "spaceSymbol",
            ) { name in
                space.setIcon(.symbol(name))
            }
            IconEmojiField(emoji: space.icon.emoji, identifierPrefix: "spaceEmoji", close: close) { chosen in
                space.setIcon(chosen.map(SidebarIcon.emoji) ?? .default)
            }
        }
    }
}
