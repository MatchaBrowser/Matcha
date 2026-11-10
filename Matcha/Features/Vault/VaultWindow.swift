import SwiftUI

/// The vault's window (Window > Vault, `VAULT.md` § 7 and § 9): locked, it asks for the password or Touch ID; open, it
/// shows the items. A single window, opened only by the user, never restored at launch.
struct VaultWindow: View {
    let vault: VaultService
    let clipboard: VaultClipboard
    let window: VaultWindowState
    @State private var model: VaultBrowserModel

    init(vault: VaultService, clipboard: VaultClipboard, window: VaultWindowState) {
        self.vault = vault
        self.clipboard = clipboard
        self.window = window
        _model = State(initialValue: VaultBrowserModel(vault: vault))
    }

    var body: some View {
        Group {
            switch vault.status {
            case let .unavailable(reason):
                VaultUnavailableView(reason: reason)
            case .locked:
                VaultUnlockView(vault: vault)
            case .unlocked:
                VaultBrowser(model: model, clipboard: clipboard, window: window)
                    .environment(vault)
            }
        }
        .navigationTitle(Text("Vault", comment: "Title of the vault's window"))
        .frame(minWidth: 760, minHeight: 460)
        // A window that shows secrets stays out of screen captures where macOS honors it (`VAULT.md` § 7.5).
        .background(VaultWindowSharing())
        .onChange(of: vault.status) { _, status in
            if status != .unlocked {
                model.draft = nil
            }
        }
        // An import asked from the menu and left locked doesn't come back at the next opening.
        .onDisappear { window.showsImport = false }
    }
}

/// Why the vault can't open, and what to do.
struct VaultUnavailableView: View {
    let reason: VaultService.Unavailability

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "lock.shield")
        } description: {
            Text(message)
        }
    }

    private var title: String {
        String(localized: "No Vault", comment: "Vault window: title when the vault can't be used")
    }

    private var message: String {
        switch reason {
        case .disabled:
            String(localized: "The vault is turned off on this Mac. Turn it on in Settings > Vault.")
        case .signedOut:
            String(localized: "The vault travels with your sync account. Sign in to sync in Settings > Sync to use it.")
        case .noVault:
            String(localized: "This sync account was created before the vault. Create a new account to use it.")
        case .serverWithoutVault:
            String(localized: "Your sync server doesn't keep vaults. Update it to use the vault.")
        case .envelopeUnreadable:
            String(localized: "The vault of this account doesn't open: its key on the server was replaced.")
        }
    }
}
