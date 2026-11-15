import SwiftUI

/// Settings > Vault (`VAULT.md` § 7.2, § 7.3): the vault turned on or off on this Mac, the automatic lock, Touch ID,
/// and locking now.
struct VaultSettingsView: View {
    let vault: VaultService
    @State private var lockDelay: TimeInterval = VaultService.defaultLockDelay
    @State private var usesTouchID = false
    @State private var touchIDError: (any Error)?
    @State private var confirmsForget = false

    var body: some View {
        Form {
            Section {
                Toggle(
                    String(localized: "Use the vault on this Mac", comment: "Settings > Vault: turns the vault on or off"),
                    isOn: Binding { vault.isEnabled } set: { vault.setEnabled($0) },
                )
                Text(
                    "Off, Matcha neither fills nor saves passwords. Your items stay in your sync account and on your other Macs.",
                    comment: "Settings > Vault: what turning the vault off does",
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            if vault.isEnabled {
                options
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            String(localized: "Forget the vault on this Mac?", comment: "Settings > Vault: confirmation"),
            isPresented: $confirmsForget,
        ) {
            Button(String(localized: "Forget", comment: "Settings > Vault: confirmation"), role: .destructive) { vault.forgetLocalVault() }
        } message: {
            Text("Its copy on this Mac is deleted. Your items stay on the server and come back at the next unlock.")
        }
        .onAppear {
            lockDelay = vault.lockDelay
            usesTouchID = vault.isTouchIDEnabled
        }
    }

    @ViewBuilder private var options: some View {
        Section {
            Picker(String(localized: "Lock the vault", comment: "Settings > Vault: automatic lock"), selection: $lockDelay) {
                ForEach(VaultService.lockDelays, id: \.self) { delay in
                    Text(Self.name(of: delay)).tag(delay)
                }
            }
            .onChange(of: lockDelay) { _, delay in vault.setLockDelay(delay) }
            Text("The vault also locks when the Mac sleeps, when its screen locks, and when Matcha quits.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        Section {
            Toggle(String(localized: "Open the vault with Touch ID", comment: "Settings > Vault"), isOn: $usesTouchID)
                .disabled(!vault.isTouchIDAvailable || !vault.isUnlocked && !usesTouchID)
                .onChange(of: usesTouchID) { _, enabled in setTouchID(enabled) }
            Text(vault.isTouchIDAvailable
                ? String(localized: "The master password is asked again every 14 days, after a restart and for exports.")
                : String(localized: "This Mac has no Touch ID, or no fingerprint."))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let touchIDError {
                Text(VaultErrorText.message(for: touchIDError)).foregroundStyle(.red).font(.caption)
            }
        }
        Section {
            Button(String(localized: "Lock the Vault Now", comment: "Settings > Vault")) { vault.lock() }
                .disabled(!vault.isUnlocked)
            Button(String(localized: "Forget the Vault on This Mac…", comment: "Settings > Vault"), role: .destructive) {
                confirmsForget = true
            }
            .disabled(vault.status == .unavailable(.signedOut))
        }
    }

    private func setTouchID(_ enabled: Bool) {
        guard enabled != vault.isTouchIDEnabled else {
            return
        }
        if enabled {
            do {
                try vault.enableTouchID()
                touchIDError = nil
            } catch {
                touchIDError = error
                usesTouchID = false
            }
        } else {
            vault.disableTouchID()
        }
    }

    static func name(of delay: TimeInterval) -> String {
        guard delay > 0 else {
            return String(localized: "Never while the Mac is awake", comment: "Settings > Vault: automatic lock")
        }
        let minutes = Int(delay / 60)
        return String(localized: "After \(minutes) min without use", comment: "Settings > Vault: automatic lock")
    }
}
