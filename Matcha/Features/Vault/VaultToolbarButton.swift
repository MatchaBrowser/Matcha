import SwiftUI

/// The vault's button, first in the row of the extensions' buttons (`ExtensionButtonsRow`): opens the vault's window,
/// and is filled while the vault is open. Shown while the vault is offered (`VaultService.isOffered`): turned on, and
/// sync signed in.
struct VaultToolbarButton: View {
    let vault: VaultService
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(SettingsSelection.self) private var settingsSelection

    var body: some View {
        Button {
            openWindow(id: MatchaApp.vaultWindowID)
        } label: {
            Label {
                Text("Vault", comment: "Title of the vault's window")
            } icon: {
                Image(systemName: vault.isUnlocked ? "lock.rectangle.stack.fill" : "lock.rectangle.stack")
            }
        }
        .help(state)
        .contextMenu {
            Button(String(localized: "Lock the Vault", comment: "Window menu: locks the vault")) { vault.lock() }
                .disabled(!vault.isUnlocked)
            Divider()
            Button(String(localized: "Vault Settings…", comment: "Vault button: context menu, opens Settings > Vault")) {
                settingsSelection.tab = .vault
                openSettings()
            }
        }
        .accessibilityValue(Text(state))
        .accessibilityIdentifier("vaultButton")
    }

    private var state: String {
        switch vault.status {
        case .unlocked: String(localized: "Vault: open", comment: "Vault button: tooltip while the vault is open")
        case .locked: String(localized: "Vault: locked", comment: "Vault button: tooltip while the vault is locked")
        case .unavailable: String(localized: "Vault", comment: "Title of the vault's window")
        }
    }
}
