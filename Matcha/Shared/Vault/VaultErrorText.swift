import Foundation

/// The message of an error of the vault, in the language of this Mac: the vault's own, the one-time codes', and those
/// of sync for a write.
enum VaultErrorText {
    static func message(for error: any Error) -> String {
        switch error {
        case let error as VaultError: message(for: error)
        case is VaultTouchID.Failure:
            String(localized: "Touch ID no longer opens the vault on this Mac. Type your master password.")
        case is OneTimeCode.Error, is Base32.Error:
            String(localized: "This one-time code isn't valid. Paste its secret or its otpauth:// address.")
        default: SyncErrorText.message(for: error)
        }
    }

    private static func message(for error: VaultError) -> String {
        switch error {
        case .locked: String(localized: "The vault is locked.")
        case .itemTooLarge: String(localized: "This item is too large for the vault. Shorten its notes or its history.")
        case .vaultFull: String(localized: "The vault is full: it holds 10,000 items at most.")
        case .wrongPassword: String(localized: "Wrong password.", comment: "Vault: the master password typed doesn't open it")
        case .unavailable: String(localized: "The vault isn't available on this Mac.")
        case .readOnly: String(localized: "This item comes from a newer version of Matcha. Update Matcha to change it.")
        case let .tooManyAttempts(until):
            String(localized: "Too many attempts. Try again at \(until.formatted(date: .omitted, time: .shortened)).")
        }
    }
}
