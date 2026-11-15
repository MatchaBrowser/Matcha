import SwiftUI

/// The locked vault (`VAULT.md` § 7.1, § 7.2): the master password, or Touch ID when it is on and the password isn't
/// due. After the first unlock with the password on a Mac with Touch ID, it is offered.
struct VaultUnlockView: View {
    let vault: VaultService
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: (any Error)?
    @State private var offersTouchID = false
    @FocusState private var isFocused: Bool

    private var canUseTouchID: Bool {
        vault.canUnlockWithTouchID(bootDate: Date.now.addingTimeInterval(-ProcessInfo.processInfo.systemUptime))
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("The vault is locked", comment: "Vault window: title of the lock screen")
                .font(.title2.bold())
            Text("Type your master password to open it.", comment: "Vault window: under the title of the lock screen")
                .foregroundStyle(.secondary)
            SecureField(text: $password, prompt: Text("Master Password", comment: "Vault window: password field")) {
                Text("Master Password", comment: "Vault window: password field")
            }
            .textFieldStyle(.roundedBorder)
            .frame(width: 280)
            .focused($isFocused)
            .onSubmit(unlockWithPassword)
            .disabled(isWorking)
            if let error {
                Text(VaultErrorText.message(for: error))
                    .foregroundStyle(.red)
                    .font(.callout)
            }
            HStack {
                if canUseTouchID {
                    Button(action: unlockWithTouchID) {
                        Label(String(localized: "Use Touch ID", comment: "Vault window: button of the lock screen"), systemImage: "touchid")
                    }
                }
                Button(String(localized: "Unlock", comment: "Vault window: button of the lock screen"), action: unlockWithPassword)
                    .keyboardShortcut(.defaultAction)
                    .disabled(password.isEmpty || isWorking)
            }
            if isWorking {
                ProgressView().controlSize(.small)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            isFocused = true
            if canUseTouchID {
                unlockWithTouchID()
            }
        }
        .alert(
            String(localized: "Open the vault with Touch ID?", comment: "Vault: offer after the first unlock"),
            isPresented: $offersTouchID,
        ) {
            Button(String(localized: "Use Touch ID", comment: "Vault window: button of the lock screen")) {
                try? vault.enableTouchID()
            }
            Button(String(localized: "Not Now", comment: "Vault: refuse Touch ID"), role: .cancel) {}
        } message: {
            Text("Your fingerprint opens the vault on this Mac. The master password is asked again every 14 days and after a restart.")
        }
    }

    private func unlockWithPassword() {
        guard !password.isEmpty, !isWorking else {
            return
        }
        isWorking = true
        let typed = password
        Task {
            do {
                try await vault.unlock(password: typed)
                password = ""
                error = nil
                if vault.isTouchIDAvailable, !vault.isTouchIDEnabled, !VaultTouchIDOffer.wasMade {
                    VaultTouchIDOffer.wasMade = true
                    offersTouchID = true
                }
            } catch {
                self.error = error
            }
            isWorking = false
        }
    }

    private func unlockWithTouchID() {
        Task {
            do {
                try await vault.unlockWithTouchID(reason: String(localized: "open the vault", comment: "Touch ID prompt: Matcha wants to…"))
            } catch VaultTouchID.Failure.invalidated {
                error = VaultTouchID.Failure.invalidated
            } catch {
                // Cancelled: the password stays.
            }
        }
    }
}

/// Touch ID is offered once per Mac (`VAULT.md` § 7.2); then it is in Settings > Vault.
enum VaultTouchIDOffer {
    static let key = "vaultTouchIDOffered"

    static var wasMade: Bool {
        get { UserDefaults.standard.bool(forKey: key) }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
}
