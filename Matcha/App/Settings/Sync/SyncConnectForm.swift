import SwiftUI

/// Settings > Sync, private server not signed in (task 7.9): the server's address, checked by `GET /v1/server`, then
/// sign in, create an account (master password typed twice, with its strength gauge and the warning that Matcha can't
/// recover it) or recover the account with the recovery key.
struct SyncConnectForm: View {
    let sync: SyncService
    /// The recovery kit to save (account created, or recovered with a new recovery key).
    let showKit: (SyncRecoveryKit) -> Void

    enum Step: Hashable {
        case signIn
        case create
        case recover
    }

    @State private var address = ""
    @State private var endpoint: SyncServerEndpoint?
    @State private var step = Step.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var invitation = ""
    @State private var recoveryKey = ""
    @State private var replacesRecoveryKey = true
    @State private var isWorking = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            serverSection
            if let endpoint {
                accountSection(endpoint)
            }
        }
        // The address and the email of the account this Mac was signed in to.
        .onAppear {
            if address.isEmpty, let server = sync.configuration.server {
                address = server.normalized
            }
            if email.isEmpty, let known = sync.configuration.email {
                email = known
            }
        }
    }

    private var serverSection: some View {
        Section {
            HStack {
                TextField("Server address", text: $address, prompt: Text(verbatim: "https://sync.example.com"))
                    .textContentType(.URL)
                    .onSubmit(checkServer)
                    .accessibilityIdentifier("syncServerField")
                Button(endpoint == nil ? "Connect" : "Change") {
                    endpoint == nil ? checkServer() : (endpoint = nil)
                }
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isWorking)
            }
        } header: {
            Text("Private Server")
        } footer: {
            if let endpoint {
                Label("\(endpoint.address.displayName) is ready.", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
            } else {
                Text("The address of your own sync server. Your data is encrypted on this Mac before leaving it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func accountSection(_ endpoint: SyncServerEndpoint) -> some View {
        Section {
            Picker("Account", selection: $step) {
                Text("Sign In").tag(Step.signIn)
                if !endpoint.info.isRegistrationClosed {
                    Text("Create Account").tag(Step.create)
                }
                Text("Forgot Password").tag(Step.recover)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            TextField("Email", text: $email)
                .textContentType(.username)
                .accessibilityIdentifier("syncEmailField")
            fields(for: endpoint)
        } footer: {
            footer
        }
    }

    @ViewBuilder private func fields(for endpoint: SyncServerEndpoint) -> some View {
        switch step {
        case .signIn:
            SecureField("Master password", text: $password)
                .textContentType(.password)
                .onSubmit(submit)
                .accessibilityIdentifier("syncPasswordField")
        case .create:
            SyncNewPasswordFields(password: $password, confirmation: $confirmation)
            if endpoint.info.requiresInvitation {
                TextField("Invitation code", text: $invitation, prompt: Text(verbatim: "K7QD-2MXP"))
                    .accessibilityIdentifier("syncInvitationField")
            }
        case .recover:
            TextField("Recovery key", text: $recoveryKey, prompt: Text(verbatim: "7KQ2-M9XD-…"))
                .font(.system(.body, design: .monospaced))
            SyncNewPasswordFields(password: $password, confirmation: $confirmation)
            Toggle("Create a new recovery key", isOn: $replacesRecoveryKey)
        }
        HStack {
            Spacer()
            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }
            Button(submitTitle, action: submit)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit || isWorking)
                .accessibilityIdentifier("syncSubmitButton")
        }
    }

    @ViewBuilder private var footer: some View {
        if let errorMessage {
            Text(verbatim: errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        } else if step == .recover {
            Text("Your other Macs will be disconnected and will ask for the new password.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var submitTitle: LocalizedStringKey {
        switch step {
        case .signIn: "Sign In"
        case .create: "Create Account"
        case .recover: "Recover Account"
        }
    }

    private var canSubmit: Bool {
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            return false
        }
        switch step {
        case .signIn:
            return !password.isEmpty
        case .create:
            return SyncPasswordStrength(password).isAcceptable && password == confirmation
        case .recover:
            return SyncRecoveryKey(text: recoveryKey) != nil && SyncPasswordStrength(password).isAcceptable && password == confirmation
        }
    }

    private func checkServer() {
        run {
            endpoint = try await sync.checkServer(address)
            if let endpoint {
                address = endpoint.address.normalized
            }
        }
    }

    private func submit() {
        guard canSubmit, let endpoint else {
            return
        }
        run {
            switch step {
            case .signIn:
                try await sync.signIn(on: endpoint, email: email, password: password)
            case .create:
                let kit = try await sync.createAccount(on: endpoint, email: email, password: password, invitation: invitation)
                showKit(kit)
            case .recover:
                guard let key = SyncRecoveryKey(text: recoveryKey) else {
                    return
                }
                let kit = try await sync.recover(
                    on: endpoint,
                    email: email,
                    recoveryKey: key,
                    newPassword: password,
                    newRecoveryKey: replacesRecoveryKey,
                )
                kit.map(showKit)
            }
            password = ""
            confirmation = ""
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await work()
            } catch {
                errorMessage = SyncErrorText.message(for: error)
            }
            isWorking = false
        }
    }
}

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

/// Strength of the new password, and the reminder that it can't be recovered.
struct SyncPasswordGauge: View {
    let strength: SyncPasswordStrength
    let mismatch: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Gauge(value: Double(strength.rawValue), in: 0 ... 4) {
                EmptyView()
            }
            .gaugeStyle(.accessoryLinearCapacity)
            .tint(color)
            .accessibilityLabel(Text("Password strength"))
            .accessibilityValue(label)
            (mismatch ? Text("The two passwords are different.") : label)
                .font(.caption)
                .foregroundStyle(mismatch ? .red : .secondary)
            Text("Matcha can't recover this password. Without it or the recovery kit, your synced data is lost.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var label: Text {
        switch strength {
        case .tooShort: Text("At least 12 characters.")
        case .weak: Text("Weak: add words, numbers or symbols.")
        case .fair: Text("Fair")
        case .good: Text("Good")
        case .strong: Text("Strong")
        }
    }

    private var color: Color {
        switch strength {
        case .tooShort, .weak: .red
        case .fair: .orange
        case .good: .yellow
        case .strong: .green
        }
    }
}
