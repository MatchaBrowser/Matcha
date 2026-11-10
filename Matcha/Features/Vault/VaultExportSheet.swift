import AppKit
import SwiftUI

/// Export of the vault (`VAULT.md` § 10): after the master password; encrypted by default with a generated passphrase of
/// 6 words, shown once, or in clear text after a warning. Files aren't exported in v1.
struct VaultExportSheet: View {
    let vault: VaultService
    @Environment(\.dismiss) private var dismiss
    @State private var accountPassword = ""
    @State private var encrypts = true
    @State private var exportPassword = Self.passphrase()
    @State private var isWorking = false
    @State private var error: (any Error)?
    @State private var omittedFiles = 0
    @State private var isDone = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Export the Vault", comment: "Vault export: title").font(.title2.bold())
            SecureField(String(localized: "Master Password", comment: "Vault window: password field"), text: $accountPassword)
            Picker(String(), selection: $encrypts) {
                Text("Encrypted (.matchavault)", comment: "Vault export: format").tag(true)
                Text("In clear text (CXF)", comment: "Vault export: format").tag(false)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            if encrypts {
                Text("Password of the export: write it down, it is shown once.", comment: "Vault export")
                TextField(String(), text: $exportPassword).font(.body.monospaced())
            } else {
                Label(
                    String(localized: "The file will hold all your passwords and secrets in clear text. Anyone who gets it can read them."),
                    systemImage: "exclamationmark.triangle.fill",
                )
                .foregroundStyle(.orange)
            }
            if isDone {
                Label(String(localized: "Exported. Files aren't exported: save them from their items."), systemImage: "checkmark.circle")
            }
            if let error {
                Text(VaultErrorText.message(for: error)).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button(String(localized: "Cancel", comment: "Vault editor")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(String(localized: "Export…", comment: "Vault export: button"), action: export)
                    .keyboardShortcut(.defaultAction)
                    .disabled(accountPassword.isEmpty || isWorking || encrypts && exportPassword.count < 12)
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private static func passphrase() -> String {
        guard let wordlist = try? PassphraseWordlist.bundled(in: .main),
              let generator = try? PassphraseGenerator(
                  wordlist: wordlist,
                  wordCount: 6,
                  separator: "-",
                  capitalizesWords: false,
                  includesDigit: false,
              )
        else {
            return ""
        }
        return generator.generate()
    }

    private func export() {
        isWorking = true
        let (typed, encrypts, exportPassword) = (accountPassword, encrypts, exportPassword)
        Task {
            defer { isWorking = false }
            do {
                try await vault.checkPassword(typed)
                let written = try VaultCXFWriter.export(vault.contentsForExport())
                let data = encrypts
                    ? try await Task.detached { try VaultExportFile.seal(written.data, password: exportPassword) }.value
                    : written.data
                let panel = NSSavePanel()
                panel.nameFieldStringValue = encrypts ? "Matcha Vault.matchavault" : "Matcha Vault.json"
                guard panel.runModal() == .OK, let url = panel.url else {
                    return
                }
                try data.write(to: url, options: [.atomic, .completeFileProtection])
                (omittedFiles, isDone, error) = (written.omittedFiles, true, nil)
            } catch {
                self.error = error
            }
        }
    }
}
