import SwiftUI

/// Customization panel of a pinned folder, opened below its row by “Customize…” (it pushes the following rows
/// down), between two lines, like the downloads panel. At the top: the folder's name, “Reset” and a close cross.
/// Then the icon (SF Symbols, or an emoji), the text color and the background color. Each choice applies right
/// away to the row and is saved with the layout. Esc closes it when it has the keyboard (it takes it on
/// opening).
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
            // Opened from a context menu: wait for the menu to close before taking the keyboard (Esc).
            try? await Task.sleep(for: .milliseconds(80))
            isFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Customize Folder", comment: "Accessibility label of the folder customization panel"))
        .accessibilityIdentifier("folderCustomizationPanel")
    }

    /// The folder, “Reset”, then the cross.
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

    /// Symbols (the folder, first, is the default icon), then the emoji.
    private var iconSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Icon")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            SymbolPickerGrid(
                symbols: SymbolChoice.folderIcons,
                selection: appearance.icon.selectedSymbol(defaultSymbol: SidebarIcon.defaultFolderSymbol),
                identifierPrefix: "folderSymbol",
            ) { name in
                update { $0.icon = name == SidebarIcon.defaultFolderSymbol ? .default : .symbol(name) }
            }
            IconEmojiField(emoji: appearance.icon.emoji, identifierPrefix: "folderEmoji", close: close) { chosen in
                update { $0.icon = chosen.map(SidebarIcon.emoji) ?? .default }
            }
        }
    }

    private func update(_ change: (inout FolderAppearance) -> Void) {
        tabManager.updateFolderAppearance(folder.id, change)
    }
}
