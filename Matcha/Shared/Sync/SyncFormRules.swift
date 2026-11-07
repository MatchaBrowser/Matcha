import Foundation

/// What the account forms of Settings > Sync accept (review TS12: the views' rules, tested apart). An address and,
/// depending on the form, a password and a Secret Key, a strong new password typed twice, or a recovery key. Also the
/// choice at the top of the pane.
enum SyncFormRules {
    /// Choice at the top of the pane (`SyncSettingsView`).
    enum PaneMode: Hashable {
        case off
        case privateServer
        case publicServer
    }

    /// Form of a private server not signed in (`SyncConnectForm`).
    enum ConnectStep: Hashable {
        case signIn
        case create
        case recover
    }

    /// A private server once signed in, configured, or just chosen; otherwise off.
    static func mode(isActive: Bool, configured: SyncConfiguration.Mode, choosesPrivateServer: Bool) -> PaneMode {
        isActive || configured == .privateServer || choosesPrivateServer ? .privateServer : .off
    }

    /// What the user typed in `SyncConnectForm`; each step reads only its own fields.
    struct ConnectFields {
        var email = ""
        var password = ""
        var confirmation = ""
        var secretKey = ""
        var recoveryKey = ""
    }

    /// Sign in (with a valid Secret Key), create an account or recover it (`SyncConnectForm`).
    static func canSubmit(_ step: ConnectStep, _ fields: ConnectFields) -> Bool {
        guard !fields.email.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        let newPasswordIsValid = SyncPasswordStrength(fields.password).isAcceptable && fields.password == fields.confirmation
        switch step {
        case .signIn:
            return !fields.password.isEmpty && SyncSecretKey(text: fields.secretKey) != nil
        case .create:
            return newPasswordIsValid
        case .recover:
            return SyncRecoveryKey(text: fields.recoveryKey) != nil && newPasswordIsValid
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
