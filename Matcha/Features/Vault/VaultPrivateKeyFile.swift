import AppKit

/// “Save the Private Key…” of an SSH key (`VAULT.md` § 9.4): a file that only its owner can read (0600), as `ssh`
/// requires.
enum VaultPrivateKeyFile {
    static func save(_ privateKey: String, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name.isEmpty ? "id_ed25519" : name.replacingOccurrences(of: "/", with: "-")
        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        FileManager.default.createFile(atPath: url.path, contents: Data(privateKey.utf8), attributes: [.posixPermissions: 0o600])
    }
}
