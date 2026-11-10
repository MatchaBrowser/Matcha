import Observation

/// What the vault's window shows when asked from elsewhere: File > Import From > Passwords File… opens its import, once
/// the vault is open. One for the app (`AppEnvironment`), like the window.
@MainActor
@Observable
final class VaultWindowState {
    var showsImport = false
}
