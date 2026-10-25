import Foundation

/// What the account forms of Settings > Sync accept (review TS12: the views' rules, tested apart). An address and,
/// depending on the form, a password, a strong new password typed twice, or a recovery key. Also the choice at the top
/// of the pane.
enum SyncFormRules {
    /// A private server once signed in, configured, or just chosen; otherwise off.
    static func mode(isActive: Bool, configured: SyncConfiguration.Mode, choosesPrivateServer: Bool) -> SyncSettingsView.Mode {
        isActive || configured == .privateServer || choosesPrivateServer ? .privateServer : .off
    }

    /// Sign in, create an account or recover it (`SyncConnectForm`).
    static func canSubmit(
        _ step: SyncConnectForm.Step,
        email: String,
        password: String,
        confirmation: String,
        recoveryKey: String,
    ) -> Bool {
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        let newPasswordIsValid = SyncPasswordStrength(password).isAcceptable && password == confirmation
        switch step {
        case .signIn:
            return !password.isEmpty
        case .create:
            return newPasswordIsValid
        case .recover:
            return SyncRecoveryKey(text: recoveryKey) != nil && newPasswordIsValid
        }
    }

    /// An action of Manage Account (`SyncAccountActionSheet`): always the current password.
    static func canConfirm(
        _ action: SyncAccountAction,
        password: String,
        newPassword: String,
        confirmation: String,
        email: String,
    ) -> Bool {
        guard !password.isEmpty else {
            return false
        }
        switch action {
        case .changePassword: return SyncPasswordStrength(newPassword).isAcceptable && newPassword == confirmation
        case .changeEmail: return email.contains("@")
        case .newRecoveryKit, .deleteAccount: return true
        }
    }
}
