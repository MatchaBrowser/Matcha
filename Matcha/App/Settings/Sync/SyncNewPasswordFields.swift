import SwiftUI

/// New master password, typed twice, with its strength gauge and the warning that Matcha can't recover it.
struct SyncNewPasswordFields: View {
    @Binding var password: String
    @Binding var confirmation: String

    var body: some View {
        SecureField("Master password", text: $password)
            .textContentType(.newPassword)
            .accessibilityIdentifier("syncNewPasswordField")
        SecureField("Confirm master password", text: $confirmation)
            .textContentType(.newPassword)
            .accessibilityIdentifier("syncConfirmPasswordField")
        SyncPasswordGauge(strength: SyncPasswordStrength(password), mismatch: !confirmation.isEmpty && confirmation != password)
    }
}
