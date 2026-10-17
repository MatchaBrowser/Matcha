import SwiftUI

/// Liste de l'historique, par jour, avec la recherche (dans la barre d'outils), le menu des lignes, la suppression
/// (touche ⌫, menu Édition > Supprimer) et « Effacer l'historique… ».
struct HistoryView: View {
    @Bindable var model: HistoryWindowModel
    let faviconService: FaviconService
    /// Nom du profil montré, s'il y en a plusieurs (message de l'effacement).
    let profileName: String?
    let open: ([HistoryRow]) -> Void

    @State private var isConfirmingClear = false

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
            open(model.rows(ids))
        }
        .onDeleteCommand {
            model.delete(model.selection)
        }
        .overlay { placeholder }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: Text("Search History"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear History…") { isConfirmingClear = true }
                    .accessibilityIdentifier("historyClearButton")
                    .disabled(!model.isReady)
            }
        }
        .confirmationDialog(Text("Clear History"), isPresented: $isConfirmingClear) {
            ForEach(HistoryPeriod.allCases) { period in
                Button(role: .destructive) {
                    model.clear(period)
                } label: {
                    Text(period.title)
                }
            }
        } message: {
            if let profileName {
                Text(
                    "Pages visited during this period are removed from the history of “\(profileName)”. Cookies and website data are kept.",
                )
            } else {
                Text("Pages visited during this period are removed from the history. Cookies and website data are kept.")
            }
        }
        .task(id: model.refreshKey) {
            // Une rafale de frappes ou de visites ne recalcule qu'une fois.
            if model.isReady {
                try? await Task.sleep(for: .milliseconds(100))
            }
            guard !Task.isCancelled else {
                return
            }
            await model.refresh()
        }
    }

    @ViewBuilder private func menu(for ids: Set<HistoryRow.ID>) -> some View {
        let rows = model.rows(ids)
        if !rows.isEmpty {
            Button("Open in New Tab") { open(rows) }
            Button("Copy Link") { TabLinkCopier.copy(rows.map(\.url)) }
            Divider()
            Button("Delete") { model.delete(ids) }
        }
    }

    @ViewBuilder private var placeholder: some View {
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

/// En-tête d'un jour : « Aujourd'hui », « Hier », sinon la date complète.
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
