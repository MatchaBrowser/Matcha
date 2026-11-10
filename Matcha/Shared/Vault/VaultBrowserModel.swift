import Foundation
import Observation

/// What the vault's window shows (`VAULT.md` § 9): a section of the sidebar, a search, the selected item, and the item
/// being edited. The items come from the open vault; secrets are opened only for the item shown, when asked.
@MainActor
@Observable
final class VaultBrowserModel {
    enum Section: Hashable, Sendable {
        case all
        case favorites
        case category(VaultCategory)
        case tag(String)
        /// Logins to look at (`VAULT.md` § 9.7).
        case security
        case trash
    }

    let vault: VaultService
    var section = Section.all
    var searchText = ""
    var selection: UUID?
    /// The item being created or changed; nil while showing.
    var draft: VaultItemDraft?
    /// The last error of a save, a trash or a deletion, to show.
    var error: (any Error)?
    /// The analysis of the logins, made when its section is shown.
    var securityReport = VaultSecurityReport([])

    init(vault: VaultService) {
        self.vault = vault
    }

    /// The items of the section that match the search: in the title, the subtitle, the addresses and the tags.
    var visibleItems: [VaultListItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return vault.items.filter { item in
            let inSection = section == .security ? securityReport.issues[item.id] != nil && !item.overview
                .isTrashed : isInSection(item.overview)
            return inSection && (query.isEmpty || matches(item.overview, query))
        }
    }

    private func isInSection(_ overview: VaultOverview) -> Bool {
        switch section {
        case .trash: overview.isTrashed
        case _ where overview.isTrashed: false
        case .all: true
        case .favorites: overview.favorite
        case let .category(category): overview.category == category
        case let .tag(tag): overview.tags.contains(tag)
        case .security: false
        }
    }

    private func matches(_ overview: VaultOverview, _ query: String) -> Bool {
        ([overview.title, overview.subtitle] + overview.urls + overview.tags).contains { $0.localizedStandardContains(query) }
    }

    /// The tags of the items out of the trash, sorted.
    var tags: [String] {
        Set(vault.items.filter { !$0.overview.isTrashed }.flatMap(\.overview.tags))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// The categories that have items, in the order of `VaultCategory.known`.
    var categories: [VaultCategory] {
        let present = Set(vault.items.filter { !$0.overview.isTrashed }.map(\.overview.category))
        return VaultCategory.known.filter(present.contains)
    }

    var selectedItem: VaultListItem? {
        vault.items.first { $0.id == selection }
    }

    func refreshSecurityReport() {
        securityReport = vault.securityReport()
    }

    /// Erases an old value of a secret (`VAULT.md` § 9.5).
    func deleteHistory(_ entry: VaultHistoryEntry, of id: UUID) {
        do {
            var content = try vault.content(of: id)
            content.details.history.removeAll { $0 == entry }
            try vault.save(content, id: id)
        } catch {
            self.error = error
        }
    }

    // MARK: Editing

    func startNewItem(_ category: VaultCategory) {
        var draft = VaultItemDraft(category: category)
        if case let .tag(tag) = section {
            draft.tags = [tag]
        }
        draft.favorite = section == .favorites
        self.draft = draft
    }

    func startEditing() {
        guard let selection, let content = try? vault.content(of: selection) else {
            return
        }
        draft = VaultItemDraft(id: selection, content: content)
    }

    /// Saves the draft; on success the item is selected and the draft closed.
    func saveDraft() {
        guard let draft else {
            return
        }
        do {
            let id = try vault.save(draft.content(), id: draft.id)
            selection = id
            self.draft = nil
            error = nil
        } catch {
            self.error = error
        }
    }

    func setTrashed(_ ids: [UUID], _ trashed: Bool) {
        do {
            try vault.setTrashed(ids, trashed)
            if trashed, let selection, ids.contains(selection) {
                self.selection = nil
            }
        } catch {
            self.error = error
        }
    }

    func deleteForever(_ ids: [UUID]) {
        do {
            try vault.deleteForever(ids)
            selection = nil
        } catch {
            self.error = error
        }
    }
}
