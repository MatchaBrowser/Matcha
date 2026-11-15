import SwiftUI

/// The selected item, its details opened for as long as it is shown (`VAULT.md` § 3.2): its fields by category, its
/// custom fields, its notes, its addresses, its old values.
struct VaultItemDetail: View {
    let model: VaultBrowserModel
    let item: VaultListItem
    let clipboard: VaultClipboard
    @State private var content: VaultItemContent?
    @State private var confirmsDeletion = false

    var body: some View {
        Form {
            if let content {
                header(content)
                fields(content)
                VaultCustomFieldsSection(fields: content.details.fields, clipboard: clipboard)
                VaultFilesSection(files: content.details.files, vault: model.vault)
                if !content.overview.urls.isEmpty {
                    Section(String(localized: "Websites", comment: "Vault: addresses of a login")) {
                        ForEach(content.overview.urls, id: \.self) { url in
                            VaultFieldRow(label: content.overview.match.name, value: url, clipboard: clipboard)
                        }
                    }
                }
                if !content.details.notes.isEmpty {
                    Section(String(localized: "Notes", comment: "Vault: notes of an item")) {
                        VaultFieldRow(label: "", value: content.details.notes, isSecret: true, clipboard: clipboard)
                    }
                }
                if content.overview.category == .sshKey, let key = content.details.credential(VaultCredentialType.sshKey) {
                    Section {
                        Button(String(localized: "Save the Private Key…", comment: "Vault: SSH key, writes the private key to a file")) {
                            VaultPrivateKeyFile.save(key.string("privateKey"), name: key.string("keyComment"))
                        }
                    }
                }
                VaultHistorySection(history: content.details.history, clipboard: clipboard) { entry in
                    model.deleteHistory(entry, of: item.id)
                }
            } else {
                ProgressView()
            }
        }
        .formStyle(.grouped)
        .task(id: item.overview) {
            content = try? model.vault.content(of: item.id)
        }
        .onDisappear { content = nil }
        .toolbar { actions }
        .confirmationDialog(
            String(localized: "Delete this item for good?", comment: "Vault: confirmation of a deletion from the trash"),
            isPresented: $confirmsDeletion,
        ) {
            Button(String(localized: "Delete", comment: "Vault: delete for good"), role: .destructive) { model.deleteForever([item.id]) }
        } message: {
            Text("It will be deleted on all your Macs. This can't be undone.", comment: "Vault: confirmation of a deletion from the trash")
        }
    }

    @ToolbarContentBuilder
    private var actions: some ToolbarContent {
        ToolbarItemGroup {
            if item.overview.isTrashed {
                Button(String(localized: "Put Back", comment: "Vault: take an item out of the trash")) { model.setTrashed([item.id], false)
                }
                Button(String(localized: "Delete…", comment: "Vault: delete for good, from the trash")) { confirmsDeletion = true }
            } else {
                Button(String(localized: "Edit", comment: "Vault: change an item")) { model.startEditing() }
                    .disabled(content?.isEditable != true)
                Button(String(localized: "Move to Trash", comment: "Vault: delete an item")) { model.setTrashed([item.id], true) }
            }
        }
    }

    private func header(_ content: VaultItemContent) -> some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: content.overview.category.symbol)
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading) {
                    Text(content.overview.title).font(.title2.bold())
                    Text(content.overview.category.name).foregroundStyle(.secondary)
                }
            }
            if item.isWaiting {
                Label(
                    String(localized: "A newer version of this item couldn't be verified yet: this is the last verified one."),
                    systemImage: "clock.badge.exclamationmark",
                )
                .foregroundStyle(.secondary)
            }
            if !content.isEditable {
                Label(
                    String(localized: "This item comes from a newer version of Matcha. Update Matcha to change it."),
                    systemImage: "arrow.down.circle",
                )
                .foregroundStyle(.secondary)
            }
            if !content.overview.tags.isEmpty {
                Text(content.overview.tags.joined(separator: ", ")).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func fields(_ content: VaultItemContent) -> some View {
        let draft = VaultItemDraft(id: item.id, content: content)
        let specs = draft.specs.filter { !draft.value($0).isEmpty }
        if !specs.isEmpty {
            Section {
                ForEach(specs, id: \.id) { spec in
                    let code = content.details.credential(VaultCredentialType.totp).flatMap(VaultItemDraft.oneTimeCode)
                    if spec.kind == .oneTimeCode, let code {
                        VaultOneTimeCodeRow(code: code, clipboard: clipboard)
                    } else {
                        VaultFieldRow(
                            label: spec.label,
                            value: draft.value(spec),
                            isSecret: spec.kind == .secret || spec.kind == .secretText,
                            isMonospaced: spec.kind == .secretText || spec.kind == .readOnly || spec.key == "password",
                            clipboard: clipboard,
                        )
                    }
                }
            }
        }
    }
}

/// The custom fields of an item.
struct VaultCustomFieldsSection: View {
    let fields: [VaultEntry]
    let clipboard: VaultClipboard

    var body: some View {
        if !fields.isEmpty {
            Section {
                ForEach(fields, id: \.id) { field in
                    VaultFieldRow(
                        label: field.string("label"),
                        value: field.string("value"),
                        isSecret: VaultFieldType(rawValue: field.string("type"))?.isSecret == true,
                        clipboard: clipboard,
                    )
                }
            }
        }
    }
}

/// The old values of the secrets (`VAULT.md` § 9.5), masked.
struct VaultHistorySection: View {
    let history: [VaultHistoryEntry]
    let clipboard: VaultClipboard
    let onDelete: (VaultHistoryEntry) -> Void

    var body: some View {
        if !history.isEmpty {
            Section {
                DisclosureGroup(String(localized: "Old Values", comment: "Vault: the history of the secrets of an item")) {
                    ForEach(history, id: \.self) { entry in
                        VaultFieldRow(
                            label: entry.date.formatted(date: .abbreviated, time: .shortened),
                            value: entry.value,
                            isSecret: true,
                            clipboard: clipboard,
                        )
                        .contextMenu {
                            Button(
                                String(localized: "Erase This Value", comment: "Vault: deletes an old value of a secret"),
                                role: .destructive,
                            ) {
                                onDelete(entry)
                            }
                        }
                    }
                }
            }
        }
    }
}
