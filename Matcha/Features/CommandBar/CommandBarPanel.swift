import SwiftUI

/// Panneau de la barre de commande : le champ, puis la liste des résultats s'il y en a.
struct CommandBarPanel: View {
    static let cornerRadius = 14.0
    static let fieldHeight = 52.0
    static let rowHeight = 36.0
    static let listPadding = 6.0

    let model: any CommandBarPanelModel
    /// ⏎ ou clic : la ligne `id` (nil : la ligne sélectionnée).
    let submit: (CommandRow.ID?) -> Void
    /// ⎋.
    let cancel: () -> Void
    let theme: SpaceTheme
    /// Hauteur maximale du panneau ; la liste défile au-delà.
    let maxHeight: Double

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            fieldRow
            if !model.rows.isEmpty {
                Divider()
                results
            }
        }
        .background {
            // Le flou ne voit pas le contenu des pages (couches de WebKit hors du processus) : le
            // panneau prend la teinte de fond de la page. Même résultat avec NSVisualEffectView.
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Command Bar", comment: "Accessibility label of the command bar panel"))
        .accessibilityIdentifier("commandBar")
    }

    // MARK: Champ

    /// Le champ garde sa place : seule l'icône qui le précède change.
    private var fieldRow: some View {
        HStack(spacing: 10) {
            leadingIcon
                .frame(width: 18, height: 18)
            CommandBarTextField(
                text: model.text,
                focusRequest: model.focusRequest,
                onTextChange: model.updateText,
                onKey: handle,
                onEditingEnded: endEditing,
            )
        }
        .padding(.horizontal, 16)
        .frame(height: Self.fieldHeight)
    }

    /// Icône du site de l'onglet modifié (⌘L), sinon une loupe.
    @ViewBuilder private var leadingIcon: some View {
        if let target = model.editedTab, target.url != nil {
            FaviconView(tab: target, size: 18)
        } else {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Résultats

    private var results: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(model.rows) { row in
                        CommandBarRowView(
                            row: row,
                            isSelected: row.id == model.selectedRowID,
                            searchEngineName: model.searchEngine.name,
                            tint: tint,
                            icons: model.rowIcons,
                        ) {
                            submit(row.id)
                        }
                        .id(row.id)
                    }
                }
                .padding(Self.listPadding)
            }
            // Une vue défilante prend toute la hauteur offerte : la sienne est donc fixée ici.
            .frame(height: min(Double(model.rows.count) * Self.rowHeight + 2 * Self.listPadding, maxHeight - Self.fieldHeight - 1))
            .onChange(of: model.selectedRowID) { _, id in
                if let id {
                    proxy.scrollTo(id)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Results", comment: "Accessibility label of the command bar result list"))
        .accessibilityIdentifier("commandBarResults")
    }

    /// Teinte de la ligne sélectionnée : première couleur du Space (gris en fenêtre privée).
    private var tint: Color {
        theme.swiftUIColors(for: colorScheme).first ?? .accentColor
    }

    // MARK: Clavier

    private func handle(_ command: CommandBarKeyCommand) {
        switch command {
        case .moveUp:
            moveSelection(by: -1)
        case .moveDown:
            moveSelection(by: 1)
        case .submit:
            submit(nil)
        case .cancel:
            cancel()
        }
    }

    /// VoiceOver lit le titre de la ligne nouvellement sélectionnée.
    private func moveSelection(by delta: Int) {
        model.moveSelection(by: delta)
        if let row = model.selectedRow {
            AccessibilityNotification.Announcement(row.title).post()
        }
    }

    /// Le champ a perdu le clavier sans passer par la barre : elle se ferme (jamais de barre « zombie »).
    private func endEditing() {
        if model.isPresented {
            model.dismiss()
        }
    }
}
