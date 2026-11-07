import SwiftUI

/// Settings > Sync, private server not signed in (task 7.9): the server's address, checked by `GET /v1/server`, then
/// sign in (master password and Secret Key, `SYNC.md` § 3.4), create an account (master password typed twice, with its
/// strength gauge and the warning that Matcha can't recover it) or recover the account with the recovery key.
struct SyncConnectForm: View {
    let sync: SyncService
    /// The recovery kit to save (account created or recovered).
    let showKit: (SyncRecoveryKit) -> Void

    typealias Step = SyncFormRules.ConnectStep

    @State private var address = ""
    @State private var endpoint: SyncServerEndpoint?
    @State private var step = Step.signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmation = ""
    @State private var invitation = ""
    @State private var secretKey = ""
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
        // The address, the email and the Secret Key of the account this Mac was signed in to.
        .onAppear {
            if address.isEmpty, let server = sync.configuration.server {
                address = server.normalized
            }
            if email.isEmpty, let known = sync.configuration.email {
                email = known
            }
            if secretKey.isEmpty, let remembered = sync.rememberedSecretKey() {
                secretKey = remembered.displayed
            }
        }
    }

    private var serverSection: some View {
        Section {
            HStack {
                TextField("Server address", text: $address, prompt: Text(verbatim: "https://sync.example.com"))
                    .textContentType(.URL)
                    .onSubmit(checkServer)
                    // The server checked is the one signed in to: “Change” first (review SY29).
                    .disabled(endpoint != nil)
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
            TextField("Secret Key", text: $secretKey, prompt: Text(verbatim: "S1-R30W-5GY4-…"))
                .font(.system(.body, design: .monospaced))
                .onSubmit(submit)
                .accessibilityIdentifier("syncSecretKeyField")
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
        } else if step == .signIn, SyncSecretKey.isMistyped(secretKey) {
            Text("The Secret Key is incorrect. Check it against your recovery kit.")
                .font(.caption)
                .foregroundStyle(.red)
        } else if step == .signIn {
            Text("Your Secret Key is in your recovery kit.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if step == .recover {
            Text("""
            Your other Macs will be disconnected. They will ask for the new password and the new Secret Key, from the \
            kit you save next.
            """)
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
        SyncFormRules.canSubmit(step, .init(
            email: email,
            password: password,
            confirmation: confirmation,
            secretKey: secretKey,
            recoveryKey: recoveryKey,
        ))
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
                guard let key = SyncSecretKey(text: secretKey) else {
                    return
                }
                try await sync.signIn(on: endpoint, email: email, password: password, secretKey: key)
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
                showKit(kit)
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
