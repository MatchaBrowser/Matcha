import SwiftUI

/// Éditeur d'un Space, dans la bulle ouverte par un clic sur l'icône du Space affiché, ou par « Changer l'icône… » et
/// « Modifier le thème… » de son menu : son nom, son icône (symboles SF ou un emoji), puis son thème. Chaque choix
/// s'applique tout de suite au Space et s'enregistre.
struct SpaceEditor: View {
    let space: SpaceSession
    /// Échap dans le champ emoji : ferme la bulle (ailleurs, la bulle se ferme d'elle-même).
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

/// Icône d'un Space, section de son éditeur : grille de symboles (celui du Space est entouré), puis l'emoji. Vider le
/// champ emoji rend le cercle, l'icône par défaut.
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

/// Titre d'une section de l'éditeur d'un Space.
struct SpaceEditorSectionTitle: View {
    let title: Text

    init(_ title: Text) {
        self.title = title
    }

    var body: some View {
        title
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }
}
