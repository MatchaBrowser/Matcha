import SwiftUI

/// File > Import From, like Safari's menu: Arc… (task 7.1), disabled outside a browsing window and in a private window;
/// Passwords File… (`VAULT.md` § 10), which opens the vault's import, absent while the vault is turned off.
struct ImportCommands: Commands {
    let vault: VaultService
    let vaultWindow: VaultWindowState
    @FocusedValue(\.windowActions) private var windowActions
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .importExport) {
            Menu("Import From") {
                Button("Arc…") { windowActions?.importFromArc?() }
                    .disabled(windowActions?.importFromArc == nil)
                if vault.isEnabled {
                    Divider()
                    Button(String(localized: "Passwords File…", comment: "File > Import From: imports passwords into the vault")) {
                        vaultWindow.showsImport = true
                        openWindow(id: MatchaApp.vaultWindowID)
                    }
                    .disabled(!vault.isOffered)
                }
            }
        }
    }
}
