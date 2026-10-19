import SwiftUI

/// Command bar panel: the field, then the list of results if there are any.
struct CommandBarPanel: View {
    static let cornerRadius = 14.0
    static let fieldHeight = 52.0
    static let rowHeight = 36.0
    static let listPadding = 6.0

    let model: any CommandBarPanelModel
    /// ⏎ or click: row `id` (nil: the selected row).
    let submit: (CommandRow.ID?) -> Void
    /// ⎋.
    let cancel: () -> Void
    let theme: SpaceTheme
    /// Maximum height of the panel; the list scrolls beyond it.
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
            // The blur does not see the content of pages (WebKit layers outside the process): the panel takes the
            // page's background tint. Same result with NSVisualEffectView.
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.25), radius: 24, y: 12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Self.cornerRadius)
                .strokeBorder(.hairline, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Command Bar", comment: "Accessibility label of the command bar panel"))
        .accessibilityIdentifier("commandBar")
    }

    // MARK: Field

    /// The field keeps its place: only the icon before it changes.
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

    /// Site icon of the modified tab (⌘L), otherwise a magnifying glass.
    @ViewBuilder private var leadingIcon: some View {
        if let target = model.editedTab, target.url != nil {
            FaviconView(tab: target, size: 18)
        } else {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Results

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
            // A scroll view takes all the height offered: its own is therefore set here.
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

    /// Tint of the selected row: first color of the Space (gray in a private window).
    private var tint: Color {
        theme.swiftUIColors(for: colorScheme).first ?? .accentColor
    }

    // MARK: Keyboard

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

    /// VoiceOver reads the title of the newly selected row.
    private func moveSelection(by delta: Int) {
        model.moveSelection(by: delta)
        if let row = model.selectedRow {
            AccessibilityNotification.Announcement(row.title).post()
        }
    }

    /// The field lost the keyboard without going through the bar: the bar closes (never a “zombie” bar).
    private func endEditing() {
        if model.isPresented {
            model.dismiss()
        }
    }
}
