import AppKit
import SwiftUI

/// History list, by day, with the search (in the toolbar), the rows' menu, deletion (⌫ key, Edit > Delete menu)
/// and “Clear History…”.
struct HistoryView: View {
    @Bindable var model: HistoryWindowModel
    let faviconService: FaviconService
    /// Name of the profile shown, if there are several (message of the clearing dialog).
    let profileName: String?
    let open: ([HistoryRow]) -> Void

    /// History window, where the “Clear History…” sheet opens.
    @State private var window: NSWindow?

    var body: some View {
        List(selection: $model.selection) {
            ForEach(model.sections) { section in
                Section {
                    ForEach(section.rows) { row in
                        HistoryRowView(row: row, faviconService: faviconService)
                    }
                } header: {
                    HistoryDayHeader(day: section.day)
                }
            }
        }
        .accessibilityIdentifier("historyList")
        .contextMenu(forSelectionType: HistoryRow.ID.self) { ids in
            menu(for: ids)
        } primaryAction: { ids in
            confirmOpen(model.rows(ids))
        }
        .onDeleteCommand {
            model.delete(model.selection)
        }
        // Apart from the list, which reads only the sections and the selection: a keystroke or a visit doesn't
        // recompute it (review IU7).
        .overlay { HistoryPlaceholder(model: model) }
        .background { HistoryRefresh(model: model) }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: Text("Search History"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear History…") {
                    HistoryClearAlert.present(in: window, profileName: profileName) { model.clear($0) }
                }
                .accessibilityIdentifier("historyClearButton")
                .disabled(!model.isReady)
            }
        }
        .background {
            WindowAccessor { window in
                Task { self.window = window }
            }
        }
    }

    /// `open`, after a confirmation for many rows.
    private func confirmOpen(_ rows: [HistoryRow]) {
        HistoryOpenConfirmation.confirm(count: rows.count, in: window) { open(rows) }
    }

    @ViewBuilder private func menu(for ids: Set<HistoryRow.ID>) -> some View {
        let rows = model.rows(ids)
        if !rows.isEmpty {
            Button("Open in New Tab") { confirmOpen(rows) }
            Button("Copy Link") { TabLinkCopier.copy(rows.map(\.url)) }
            Divider()
            Button("Delete") { model.delete(ids) }
        }
    }
}

/// Header of a day: “Today”, “Yesterday”, otherwise the full date.
private struct HistoryDayHeader: View {
    let day: HistoryDay

    var body: some View {
        switch day {
        case .today:
            Text("Today", comment: "History section of the pages visited today")
        case .yesterday:
            Text("Yesterday", comment: "History section of the pages visited yesterday")
        case let .date(start):
            Text(start, format: .dateTime.weekday(.wide).day().month(.wide).year())
        }
    }
}

/// Recomputes the sections when the history, the profile or the searched text change.
private struct HistoryRefresh: View {
    let model: HistoryWindowModel

    var body: some View {
        Color.clear
            .task(id: model.refreshKey) {
                let delay = model.refreshDelay
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                }
                guard !Task.isCancelled else {
                    return
                }
                await model.refresh()
            }
    }
}

/// Over the list: a progress indicator until the first sections, “No History”, or no result for the search.
private struct HistoryPlaceholder: View {
    let model: HistoryWindowModel

    var body: some View {
        if !model.isReady {
            ProgressView()
        } else if model.sections.isEmpty {
            if model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView {
                    Label("No History", systemImage: "clock")
                } description: {
                    Text("Pages you visit appear here.")
                }
            } else {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
    }
}
