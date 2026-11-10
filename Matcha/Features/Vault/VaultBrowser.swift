import AppKit
import SwiftUI

/// The open vault: its sections, the items of the section shown, and the selected item, in detail or being edited.
struct VaultBrowser: View {
    @Bindable var model: VaultBrowserModel
    let clipboard: VaultClipboard
    @Bindable var window: VaultWindowState
    @State private var showsExport = false

    var body: some View {
        NavigationSplitView {
            VaultSidebar(model: model)
                .navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } content: {
            VaultItemList(model: model, importItems: { window.showsImport = true })
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 420)
        } detail: {
            if let draft = Binding($model.draft) {
                VaultItemEditor(draft: draft, onSave: model.saveDraft, onCancel: { model.draft = nil })
            } else if let item = model.selectedItem {
                VaultItemDetail(model: model, item: item, clipboard: clipboard)
                    .id(item.id)
            } else {
                Text("Select an item", comment: "Vault window: nothing selected")
                    .foregroundStyle(.secondary)
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: Text("Search the Vault", comment: "Vault window: search field"))
        .toolbar {
            ToolbarItem {
                Menu {
                    ForEach(VaultCategory.known, id: \.self) { category in
                        Button {
                            model.startNewItem(category)
                        } label: {
                            Label(category.name, systemImage: category.symbol)
                        }
                    }
                } label: {
                    Label(String(localized: "New Item", comment: "Vault window: toolbar menu"), systemImage: "plus")
                }
            }
            ToolbarItem {
                Menu {
                    Button(String(localized: "Import…", comment: "Vault editor: import an SSH key from a file")) {
                        window.showsImport = true
                    }
                    Button(String(localized: "Export…", comment: "Vault export: button")) { showsExport = true }
                } label: {
                    Label(
                        String(localized: "Import and Export", comment: "Vault window: toolbar menu"),
                        systemImage: "square.and.arrow.up.on.square",
                    )
                }
            }
            ToolbarItem {
                Button {
                    model.vault.lock()
                } label: {
                    Label(String(localized: "Lock", comment: "Vault window: toolbar button that locks the vault"), systemImage: "lock")
                }
            }
        }
        .safeAreaInset(edge: .top) {
            VaultNoticeBanner(vault: model.vault)
        }
        .alert(
            String(localized: "The vault couldn't do it", comment: "Vault window: title of an error"),
            isPresented: Binding { model.error != nil } set: {
                if !$0 {
                    model.error = nil
                }
            },
        ) {
            Button("OK") { model.error = nil }
        } message: {
            Text(model.error.map(VaultErrorText.message) ?? "")
        }
        .sheet(isPresented: $window.showsImport) { VaultImportSheet(vault: model.vault) }
        .sheet(isPresented: $showsExport) { VaultExportSheet(vault: model.vault) }
        .onChange(of: model.selection) { model.vault.noteActivity() }
        .onAppear { model.vault.purgeTrash() }
    }
}

/// What the last verification found (`VAULT.md` § 5.2, § 5.3), and the last write that failed.
struct VaultNoticeBanner: View {
    let vault: VaultService

    var body: some View {
        if let text {
            Label(text, systemImage: "exclamationmark.shield")
                .font(.callout)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.yellow.opacity(0.15))
        }
    }

    private var text: String? {
        if let error = vault.writeError {
            return VaultErrorText.message(for: error)
        }
        switch vault.notice {
        case .completedFromThisMac:
            return String(
                localized: "The server's vault was older or incomplete (restored, or tampered with). Matcha completed it from this Mac.",
            )
        case .itemsWaiting:
            return String(localized: "Some items of the vault couldn't be verified yet. Matcha shows their last verified version.")
        case .waitingForAnotherMac:
            return String(localized: "The vault is waiting for another of your Macs to be verified.")
        case nil:
            return nil
        }
    }
}

/// Keeps the window that shows secrets out of screen captures, where macOS honors it (`VAULT.md` § 7.5).
struct VaultWindowSharing: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { view.window?.sharingType = .none }
        return view
    }

    func updateNSView(_ view: NSView, context _: Context) {
        view.window?.sharingType = .none
    }
}
