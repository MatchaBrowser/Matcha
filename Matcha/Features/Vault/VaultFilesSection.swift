import AppKit
import SwiftUI

/// The files of an item (`VAULT.md` § 6): opened from a temporary folder that the lock empties, or saved where the
/// user chooses.
struct VaultFilesSection: View {
    let files: [VaultEntry]
    let vault: VaultService
    @State private var working: String?
    @State private var error: (any Error)?

    var body: some View {
        if !files.isEmpty {
            Section(String(localized: "Files", comment: "Vault: files of an item")) {
                ForEach(files, id: \.id) { file in
                    HStack {
                        Image(systemName: "doc")
                        VStack(alignment: .leading) {
                            Text(file.string("name"))
                            Text(ByteCountFormatter.string(fromByteCount: Int64(file.integer("size") ?? 0), countStyle: .file))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if working == file.id {
                            ProgressView().controlSize(.small)
                        }
                        Button(String(localized: "Open", comment: "Vault: open a file of an item")) { open(file) }
                        Button(String(localized: "Save As…", comment: "Vault: save a file of an item")) { saveAs(file) }
                    }
                    .disabled(working != nil)
                }
                if let error {
                    Text(VaultErrorText.message(for: error)).foregroundStyle(.red).font(.caption)
                }
            }
        }
    }

    private func open(_ file: VaultEntry) {
        run(file) { try await NSWorkspace.shared.open(vault.open(file)) }
    }

    private func saveAs(_ file: VaultEntry) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = file.string("name")
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        run(file) { try await vault.download(file).write(to: url, options: .atomic) }
    }

    private func run(_ file: VaultEntry, _ work: @escaping @MainActor () async throws -> Void) {
        working = file.id
        Task {
            do {
                try await work()
                error = nil
            } catch {
                self.error = error
            }
            working = nil
        }
    }
}

/// Files in the editor: added from the disk (sent at once, encrypted), or removed.
struct VaultFilesEditor: View {
    @Binding var files: [VaultEntry]
    @Environment(VaultService.self) private var vault: VaultService?
    @State private var isSending = false
    @State private var error: (any Error)?

    var body: some View {
        Section(String(localized: "Files", comment: "Vault: files of an item")) {
            ForEach(files.indices, id: \.self) { index in
                HStack {
                    Text(files[index].string("name"))
                    Spacer()
                    Button(role: .destructive) { files.remove(at: index) } label: { Image(systemName: "minus.circle") }
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                Button(String(localized: "Add a File…", comment: "Vault editor"), action: add)
                    .disabled(isSending || vault == nil)
                if isSending {
                    ProgressView().controlSize(.small)
                }
            }
            Text("100 MB at most per file.", comment: "Vault editor: limit of a file")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let error {
                Text(VaultErrorText.message(for: error)).foregroundStyle(.red).font(.caption)
            }
        }
    }

    private func add() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        guard let vault, panel.runModal() == .OK, let url = panel.url else {
            return
        }
        isSending = true
        Task {
            do {
                try await files.append(vault.uploadFile(at: url))
                error = nil
            } catch {
                self.error = error
            }
            isSending = false
        }
    }
}
