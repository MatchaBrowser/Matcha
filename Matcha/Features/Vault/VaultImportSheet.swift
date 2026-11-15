import AppKit
import SwiftUI

/// Import into the vault (`VAULT.md` § 10): a file of Chrome, Safari, Firefox, Bitwarden, 1Password, CXF or a Matcha
/// export; what will be imported, the duplicates and what can't be, then one write. Matcha never copies the file.
struct VaultImportSheet: View {
    let vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @State private var data: Data?
    @State private var needsPassword = false
    @State private var password = ""
    @State private var result: VaultImportResult?
    @State private var duplicates = IndexSet()
    @State private var skipsDuplicates = true
    @State private var error: (any Error)?
    @State private var imported: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import into the Vault", comment: "Vault import: title").font(.title2.bold())
            Text("Logins exported by Chrome, Safari or Firefox (CSV), Bitwarden (JSON), 1Password (1PUX), a CXF file, or a Matcha export.")
                .foregroundStyle(.secondary)
            if needsPassword {
                SecureField(
                    String(localized: "Password of the export", comment: "Vault import: password of a .matchavault"),
                    text: $password,
                )
                .onSubmit(read)
            }
            if let result {
                summary(result)
            }
            if let imported {
                Label(
                    String(
                        localized: "\(imported) items imported. Delete the file you imported from: it holds your passwords in clear text.",
                    ),
                    systemImage: "checkmark.circle",
                )
            }
            if let error {
                Text(message(error)).foregroundStyle(.red)
            }
            HStack {
                Button(String(localized: "Choose a File…", comment: "Vault import"), action: choose)
                Spacer()
                Button(String(localized: "Cancel", comment: "Vault editor")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Import", comment: "Vault import: button"), action: importItems)
                    .keyboardShortcut(.defaultAction)
                    .disabled(result?.items.isEmpty ?? true || imported != nil)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private func summary(_ result: VaultImportResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(result.items.count) items to import", comment: "Vault import: summary")
            if !duplicates.isEmpty {
                let skip = String(localized: "Skip \(duplicates.count) items already in the vault", comment: "Vault import: duplicates")
                Toggle(skip, isOn: $skipsDuplicates)
            }
            if !result.issues.isEmpty {
                Text(
                    "\(result.issues.count) things couldn't be imported: attachments, passkeys or unknown fields.",
                    comment: "Vault import",
                )
                .foregroundStyle(.secondary)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        (result, imported, error, password) = (nil, nil, nil, "")
        do {
            let contents = try VaultImporter.contents(of: url)
            data = contents
            needsPassword = VaultImporter.format(of: contents) == .matchaVault
            if !needsPassword {
                read()
            }
        } catch {
            self.error = error
        }
    }

    private func read() {
        guard let data else {
            return
        }
        let typed = needsPassword ? password : nil
        Task {
            do {
                let read = try await Task.detached { try VaultImporter.read(data, password: typed) }.value
                result = read
                duplicates = VaultImportDuplicates.duplicates(in: read.items, existing: vault.existingContents())
                error = nil
            } catch {
                self.error = error
            }
        }
    }

    private func importItems() {
        guard let result else {
            return
        }
        let items = result.items.enumerated().filter { !(skipsDuplicates && duplicates.contains($0.offset)) }.map(\.element)
        let tag = String(
            localized: "Import \(Date.now.formatted(date: .numeric, time: .omitted))",
            comment: "Vault import: tag of the items",
        )
        do {
            imported = try vault.importItems(items, tag: tag)
        } catch {
            self.error = error
        }
    }

    private static let encryptedExport = String(
        localized: "This export is encrypted. Export it again without a password, then delete it after the import.",
    )

    private func message(_ error: any Error) -> String {
        switch error as? VaultImportError {
        case .unknownFormat?: String(localized: "Matcha doesn't know this file's format.", comment: "Vault import")
        case .encryptedExport?: Self.encryptedExport
        case .wrongPassword?: String(localized: "Wrong password.", comment: "Vault: the master password typed doesn't open it")
        case .tooLarge?: String(localized: "This file is too large to import.", comment: "Vault import")
        case nil: VaultErrorText.message(for: error)
        default: String(localized: "This file can't be read.", comment: "Vault import")
        }
    }
}
