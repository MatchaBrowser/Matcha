import SwiftUI

/// Settings > Sync (task 7.9, `SYNC.md` § 1): off, a private server, or the public server (coming soon). With a private
/// server: sign in or create an account, then the state of sync, the account's avatar (with a server that keeps it),
/// the devices and the account. iCloud will come with its resumption (`FEATURES.md`).
struct SyncSettingsView: View {
    enum Mode: Hashable {
        case off
        case privateServer
        case publicServer
    }

    @Environment(SyncService.self) private var sync
    @State private var choosesPrivateServer = false
    @State private var confirmsTurningOff = false
    @State private var kit: SyncRecoveryKit?

    var body: some View {
        Form {
            Section {
                Picker("Sync", selection: modeBinding) {
                    Text("Off").tag(Mode.off)
                    Text("Private Server").tag(Mode.privateServer)
                    Text("Public Server (Coming Soon)").tag(Mode.publicServer)
                        .selectionDisabled()
                }
                .accessibilityIdentifier("syncModePicker")
            } footer: {
                Text("""
                Your Spaces, folders, Favorites, pinned and today tabs, extensions and settings, on all your Macs. \
                Everything is encrypted on this Mac with your master password: the server can't read it.
                """, comment: "Settings > Sync: what sync does")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if mode == .privateServer {
                if sync.isActive {
                    SyncAccountSection(sync: sync) { kit = $0 }
                    if sync.supportsAvatar {
                        SyncAvatarSection(sync: sync)
                    }
                    SyncDevicesSection(sync: sync)
                } else {
                    if let reason = sync.configuration.signedOutReason {
                        Section {
                            Label(message(for: reason), systemImage: "exclamationmark.circle")
                                .foregroundStyle(.orange)
                        }
                    }
                    SyncConnectForm(sync: sync) { kit = $0 }
                }
            }
        }
        .formStyle(.grouped)
        // The window takes the height of its content, which changes when signing in: no scroll bar.
        .scrollDisabled(true)
        .fixedSize(horizontal: false, vertical: true)
        .asksSyncQuestions()
        .sheet(item: Binding { kit ?? sync.pendingRecoveryKit } set: {
            if $0 == nil {
                kit = nil
            }
        }) { shown in
            SyncRecoveryKitView(kit: shown) {
                kit = nil
                if sync.pendingRecoveryKit != nil {
                    sync.recoveryKitSaved()
                }
            }
            .interactiveDismissDisabled()
        }
        .confirmationDialog("Turn off sync?", isPresented: $confirmsTurningOff) {
            Button("Turn Off") {
                choosesPrivateServer = false
                Task { await sync.signOut() }
            }
        } message: {
            Text("Your tabs, Spaces and settings stay on this Mac. They no longer sync with your other Macs.")
        }
    }

    private var mode: Mode {
        sync.isActive || sync.configuration.mode == .privateServer || choosesPrivateServer ? .privateServer : .off
    }

    private var modeBinding: Binding<Mode> {
        Binding { mode } set: { newMode in
            switch newMode {
            case .privateServer:
                choosesPrivateServer = true
            case .off:
                if sync.isActive {
                    confirmsTurningOff = true
                } else {
                    choosesPrivateServer = false
                    Task { await sync.signOut() }
                }
            case .publicServer:
                break
            }
        }
    }

    private func message(for reason: SyncConfiguration.SignedOutReason) -> LocalizedStringKey {
        switch reason {
        case .deviceRevoked: "This Mac was disconnected from sync. Sign in again to resume."
        case .accountDeleted: "This sync account was deleted from another device."
        case .sessionExpired: "Sign in again to keep syncing."
        case .copiedMac: "This Mac looks like a copy of another one. Sign in again to give it its own identity."
        }
    }
}

extension SyncRecoveryKit: Identifiable {
    var id: String {
        recoveryKey
    }
}
