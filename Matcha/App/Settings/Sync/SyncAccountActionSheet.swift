import SwiftUI

/// Sensitive operations on the sync account (`SYNC.md` § 4.1): they ask for the master password again.
enum SyncAccountAction: String, Identifiable {
    case changePassword
    case newRecoveryKit
    case changeEmail
    case deleteAccount

    var id: String {
        rawValue
    }
}

/// Sheet of an account operation: the current password, and what the operation needs.
struct SyncAccountActionSheet: View {
    let sync: SyncService
    let action: SyncAccountAction

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var newPassword = ""
    @State private var confirmation = ""
    @State private var email = ""
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.weight(.semibold))
            Text(explanation)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(.secondary)
            Form {
                SecureField("Current master password", text: $password)
                    .textContentType(.password)
                switch action {
                case .changePassword:
                    SyncNewPasswordFields(password: $newPassword, confirmation: $confirmation)
                case .changeEmail:
                    TextField("New email", text: $email)
                        .textContentType(.username)
                case .newRecoveryKit, .deleteAccount:
                    EmptyView()
                }
            }
            .formStyle(.columns)
            if let errorMessage {
                Text(verbatim: errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                }
                // An operation started can't be left: its error would be lost (review SY30).
                Button("Cancel", role: .cancel) { dismiss() }
                    .disabled(isWorking)
                Button(confirmTitle, role: action == .deleteAccount ? .destructive : nil, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canConfirm || isWorking)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var title: LocalizedStringKey {
        switch action {
        case .changePassword: "Change Master Password"
        case .newRecoveryKit: "New Recovery Kit"
        case .changeEmail: "Change Email"
        case .deleteAccount: "Delete Sync Account"
        }
    }

    private var explanation: LocalizedStringKey {
        switch action {
        case .changePassword:
            "Your data isn't encrypted again. Your other Macs are disconnected and ask for the new password."
        case .newRecoveryKit:
            "A new recovery key replaces the old one, which stops working. Save the new kit."
        case .changeEmail:
            "Your Macs stay signed in. The recovery kit shows the email: save a new one afterwards."
        case .deleteAccount:
            "Your synced data is deleted from the server, for all your Macs. Each Mac keeps its own tabs and Spaces."
        }
    }

    private var confirmTitle: LocalizedStringKey {
        switch action {
        case .changePassword: "Change Password"
        case .newRecoveryKit: "Create Kit"
        case .changeEmail: "Change Email"
        case .deleteAccount: "Delete Account"
        }
    }

    private var canConfirm: Bool {
        SyncFormRules.canConfirm(action, password: password, newPassword: newPassword, confirmation: confirmation, email: email)
    }

    private func confirm() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                switch action {
                case .changePassword:
                    try await sync.changePassword(current: password, new: newPassword)
                case .newRecoveryKit:
                    // Kept by sync until saved (`pendingRecoveryKit`): shown once this sheet is gone (review SY12).
                    _ = try await sync.replaceRecoveryKey(password: password)
                case .changeEmail:
                    try await sync.changeEmail(password: password, to: email)
                case .deleteAccount:
                    try await sync.deleteAccount(password: password)
                }
                dismiss()
            } catch {
                errorMessage = SyncErrorText.message(for: error)
            }
            isWorking = false
        }
    }
}
