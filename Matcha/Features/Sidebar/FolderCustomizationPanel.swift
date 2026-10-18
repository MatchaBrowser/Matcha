import SwiftUI

/// Panneau de personnalisation d'un dossier d'épinglés, ouvert sous sa ligne par « Personnaliser… » (il pousse les
/// lignes suivantes), entre deux traits, comme le panneau des téléchargements. En tête : le nom du dossier,
/// « Réinitialiser » et une croix. Puis l'icône (symboles SF, ou un emoji), la couleur du texte et celle du fond.
/// Chaque choix s'applique tout de suite à la ligne et s'enregistre avec le rangement. Échap le ferme quand il a le
/// clavier (il le prend à l'ouverture).
struct FolderCustomizationPanel: View {
    let folder: PinnedFolder
    let tabManager: TabManager
    let close: () -> Void

    @FocusState private var isFocused: Bool

    private var appearance: FolderAppearance {
        folder.appearance
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            header
                .padding(.top, 8)
                .padding(.bottom, 6)
            VStack(alignment: .leading, spacing: 12) {
                iconSection
                FolderColorRow(
                    title: "Text",
                    pickerTitle: "Custom Text Color",
                    selection: appearance.textColor,
                    identifier: "folderTextColor",
                ) { color in
                    update { $0.textColor = color }
                }
                FolderColorRow(
                    title: "Background",
                    pickerTitle: "Custom Background Color",
                    selection: appearance.backgroundColor,
                    identifier: "folderBackgroundColor",
                ) { color in
                    update { $0.backgroundColor = color }
                }
            }
            .padding(.bottom, 10)
            Divider()
        }
        .padding(.vertical, 4)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onExitCommand(perform: close)
        .task {
            // Ouvert depuis un menu contextuel : on attend sa fermeture pour prendre le clavier (Échap).
            try? await Task.sleep(for: .milliseconds(80))
            isFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Customize Folder", comment: "Accessibility label of the folder customization panel"))
        .accessibilityIdentifier("folderCustomizationPanel")
    }

    /// Le dossier, « Réinitialiser », puis la croix.
    private var header: some View {
        HStack(spacing: 8) {
            Text(folder.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityIdentifier("folderCustomizationTitle")
            Spacer(minLength: 0)
            Button {
                tabManager.setFolderAppearance(folder.id, .default)
            } label: {
                Text("Reset", comment: "Folder customization: restore the default icon and colors")
                    .font(.caption.weight(.medium))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .disabled(appearance.isDefault)
            .help("Restore the default icon and colors")
            .accessibilityIdentifier("folderAppearanceResetButton")
            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(SidebarIconButtonStyle())
            .help("Close Customization")
            .accessibilityLabel(Text("Close Customization"))
            .accessibilityIdentifier("folderCustomizationCloseButton")
        }
    }

    /// Symboles (le dossier, en premier, est l'icône par défaut), puis l'emoji.
    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Icon")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            SymbolPickerGrid(symbols: SymbolChoice.folderIcons, selection: selectedSymbol, identifierPrefix: "folderSymbol") { name in
                update { $0.icon = name == Self.defaultSymbol ? .default : .symbol(name) }
            }
            FolderEmojiField(emoji: emoji, close: close) { chosen in
                update { $0.icon = chosen.map(FolderIcon.emoji) ?? .default }
            }
        }
    }

    private static let defaultSymbol = "folder"

    private var selectedSymbol: String? {
        switch appearance.icon {
        case .default: Self.defaultSymbol
        case let .symbol(name): name
        case .emoji: nil
        }
    }

    private var emoji: String? {
        if case let .emoji(emoji) = appearance.icon {
            return emoji
        }
        return nil
    }

    private func update(_ change: (inout FolderAppearance) -> Void) {
        tabManager.updateFolderAppearance(folder.id, change)
    }
}
