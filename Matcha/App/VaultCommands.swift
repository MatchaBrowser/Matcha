import SwiftUI

/// Window > Vault and Window > Lock the Vault (`VAULT.md` § 7.3), absent while the vault is turned off on this Mac.
/// Their shortcuts are fixed: no menu command can take them (`MenuShortcut.fixedKeys`).
struct VaultCommands: Commands {
    let vault: VaultService
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(before: .windowList) {
            if vault.isEnabled {
                Button(String(localized: "Vault", comment: "Title of the vault's window")) {
                    openWindow(id: MatchaApp.vaultWindowID)
                }
                .keyboardShortcut("p", modifiers: [.command, .option])
                Button(String(localized: "Lock the Vault", comment: "Window menu: locks the vault")) {
                    vault.lock()
                }
                .keyboardShortcut("l", modifiers: [.command, .control])
                .disabled(!vault.isUnlocked)
                Divider()
            }
        }
    }
}
