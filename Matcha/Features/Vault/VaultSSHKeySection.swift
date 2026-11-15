import AppKit
import SwiftUI

/// An SSH key in the editor (`VAULT.md` § 9.4): generated here, or imported from a file or from pasted text (with its
/// passphrase if it is encrypted, the key being kept decrypted: the vault protects it). Off the main thread: RSA and
/// bcrypt take a moment.
struct VaultSSHKeySection: View {
    @Binding var draft: VaultItemDraft
    @State private var type = SSHKeyType.ed25519
    @State private var passphrase = ""
    @State private var needsPassphrase = false
    @State private var pending: String?
    @State private var isWorking = false
    @State private var error: SSHKeyError?

    var body: some View {
        Section(String(localized: "Key", comment: "Vault editor: section of an SSH key")) {
            HStack {
                Picker(String(localized: "Type", comment: "Vault: field of a card (Visa, Mastercard…)"), selection: $type) {
                    ForEach(SSHKeyType.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                Button(String(localized: "Generate", comment: "Vault editor: generate an SSH key"), action: generate)
                Button(String(localized: "Import…", comment: "Vault editor: import an SSH key from a file"), action: chooseFile)
            }
            .disabled(isWorking)
            if needsPassphrase {
                HStack {
                    SecureField(String(localized: "Passphrase of the key", comment: "Vault editor: SSH key"), text: $passphrase)
                    Button(String(localized: "Decrypt", comment: "Vault editor: SSH key")) { pending.map { importText($0) } }
                }
            }
            if let error {
                Text(message(error)).foregroundStyle(.red).font(.callout)
            }
            if isWorking {
                ProgressView().controlSize(.small)
            }
        }
    }

    private func generate() {
        let (type, comment) = (type, draft.values["ssh-key.keyComment"] ?? "")
        run { try SSHKeyGenerator.generate(type, comment: comment) }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? FileHandle(forReadingFrom: url).read(upToCount: SSHKeyImporter.maximumTextSize + 1),
              let text = String(bytes: data, encoding: .utf8)
        else {
            return
        }
        importText(text)
    }

    private func importText(_ text: String) {
        let phrase = passphrase.isEmpty ? nil : passphrase
        pending = text
        run { try SSHKeyImporter.importKey(text, passphrase: phrase) }
    }

    private func run(_ work: @escaping @Sendable () throws -> SSHKey) {
        isWorking = true
        Task {
            let result = await Task.detached { Result { try work() } }.value
            isWorking = false
            switch result {
            case let .success(key):
                fill(key)
            case let .failure(failure as SSHKeyError):
                needsPassphrase = failure == .needsPassphrase || failure == .wrongPassphrase || needsPassphrase
                error = failure == .needsPassphrase ? nil : failure
            case .failure:
                error = .malformed
            }
        }
    }

    private func fill(_ key: SSHKey) {
        draft.values["ssh-key.privateKey"] = key.privateKey
        draft.values["ssh-key.publicKey"] = key.publicKey
        draft.values["ssh-key.fingerprint"] = key.fingerprint
        draft.values["ssh-key.keyComment"] = key.comment
        draft.values["ssh-key.keyType"] = key.keyType.rawValue
        if draft.title.isEmpty {
            draft.title = key.comment.isEmpty ? key.keyType.rawValue : key.comment
        }
        (needsPassphrase, passphrase, pending, error) = (false, "", nil, nil)
    }

    private func message(_ error: SSHKeyError) -> String {
        switch error {
        case .wrongPassphrase: String(localized: "Wrong passphrase.", comment: "Vault editor: SSH key")
        case .weakRSA: String(localized: "This RSA key is too short: 2,048 bits at least.", comment: "Vault editor: SSH key")
        case .encryptedPEM: String(localized: "Encrypted PEM keys aren't supported. Convert it with ssh-keygen -p first.")
        default: String(localized: "This isn't a private key Matcha can read.", comment: "Vault editor: SSH key")
        }
    }
}
