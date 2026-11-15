import SwiftUI

/// Sections of the vault: all items, favorites, each category, each tag, the trash.
struct VaultSidebar: View {
    @Bindable var model: VaultBrowserModel

    var body: some View {
        List(selection: $model.section) {
            Section {
                Label(String(localized: "All Items", comment: "Vault window: sidebar"), systemImage: "tray.full")
                    .tag(VaultBrowserModel.Section.all)
                Label(String(localized: "Favorites", comment: "Vault window: sidebar"), systemImage: "star")
                    .tag(VaultBrowserModel.Section.favorites)
                Label(
                    String(localized: "Password Check", comment: "Vault window: sidebar, weak, reused or insecure passwords"),
                    systemImage: "exclamationmark.shield",
                )
                .tag(VaultBrowserModel.Section.security)
            }
            Section(String(localized: "Categories", comment: "Vault window: sidebar section")) {
                ForEach(model.categories, id: \.self) { category in
                    Label(category.name, systemImage: category.symbol)
                        .tag(VaultBrowserModel.Section.category(category))
                }
            }
            if !model.tags.isEmpty {
                Section(String(localized: "Tags", comment: "Vault window: sidebar section")) {
                    ForEach(model.tags, id: \.self) { tag in
                        Label(tag, systemImage: "tag")
                            .tag(VaultBrowserModel.Section.tag(tag))
                    }
                }
            }
            Section {
                Label(String(localized: "Trash", comment: "Vault window: sidebar"), systemImage: "trash")
                    .tag(VaultBrowserModel.Section.trash)
            }
        }
        .listStyle(.sidebar)
        .onChange(of: model.section) { _, section in
            if section == .security {
                model.refreshSecurityReport()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let date = model.vault.lastModifiedAt {
                Text(
                    "Last change \(date.formatted(date: .abbreviated, time: .shortened))",
                    comment: "Vault window: last write of the vault",
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(8)
            }
        }
    }
}

/// The items of the section, with their category, their subtitle, and whether they wait for verification.
struct VaultItemList: View {
    @Bindable var model: VaultBrowserModel
    /// Opens the import (`VaultImportSheet`), offered while the vault is empty.
    let importItems: () -> Void
    @State private var confirmsEmptyTrash = false

    var body: some View {
        List(model.visibleItems, selection: $model.selection) { item in
            HStack {
                Image(systemName: item.overview.category.symbol)
                    .foregroundStyle(.secondary)
                    .frame(width: 20)
                VStack(alignment: .leading) {
                    Text(item.overview.title.isEmpty ? String(localized: "Untitled", comment: "Vault: an item without title") : item
                        .overview.title)
                        .lineLimit(1)
                    if !item.overview.subtitle.isEmpty {
                        Text(item.overview.subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let issues = model.securityReport.issues[item.id], model.section == .security {
                    Text(VaultSecurityText.summary(issues)).font(.caption).foregroundStyle(.orange)
                }
                if item.isWaiting {
                    Image(systemName: "clock.badge.exclamationmark")
                        .help(String(
                            localized: "Waiting for verification",
                            comment: "Vault window: an item whose cited version hasn't arrived",
                        ))
                }
                if item.overview.favorite {
                    Image(systemName: "star.fill").foregroundStyle(.yellow)
                }
            }
            .contextMenu { menu(for: item) }
        }
        .overlay {
            if model.vault.items.isEmpty {
                ContentUnavailableView {
                    Label(
                        String(localized: "The Vault Is Empty", comment: "Vault window: no item at all"),
                        systemImage: "lock.rectangle.stack",
                    )
                } description: {
                    Text(
                        "Import the passwords of another browser or password manager, or add an item with +.",
                        comment: "Vault window: no item at all",
                    )
                } actions: {
                    Button(String(localized: "Import Passwords…", comment: "Vault window: opens the import"), action: importItems)
                }
            } else if model.visibleItems.isEmpty {
                ContentUnavailableView(
                    String(localized: "No Items", comment: "Vault window: empty list"),
                    systemImage: "lock.rectangle.stack",
                )
            }
        }
        .toolbar {
            if model.section == .trash, !model.visibleItems.isEmpty {
                Button(String(localized: "Empty Trash", comment: "Vault window: button")) { confirmsEmptyTrash = true }
            }
        }
        .confirmationDialog(
            String(
                localized: "Delete \(model.visibleItems.count) items for good?",
                comment: "Vault: confirmation before emptying the trash",
            ),
            isPresented: $confirmsEmptyTrash,
        ) {
            Button(String(localized: "Empty Trash", comment: "Vault window: button"), role: .destructive) {
                model.deleteForever(model.visibleItems.map(\.id))
            }
        } message: {
            Text("They will be deleted on all your Macs. This can't be undone.", comment: "Vault: confirmation before emptying the trash")
        }
    }

    @ViewBuilder
    private func menu(for item: VaultListItem) -> some View {
        if item.overview.isTrashed {
            Button(String(localized: "Put Back", comment: "Vault: take an item out of the trash")) { model.setTrashed([item.id], false) }
        } else {
            Button(String(localized: "Move to Trash", comment: "Vault: delete an item")) { model.setTrashed([item.id], true) }
        }
    }
}
