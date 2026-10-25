import SwiftUI

/// Settings > Sync, signed in (task 7.9): the account and its server, the state of sync (“Synced 2 minutes ago”,
/// understandable errors, warnings), “Sync Now”, and the account actions in one menu.
struct SyncAccountSection: View {
    let sync: SyncService
    let showKit: (SyncRecoveryKit) -> Void

    @State private var action: SyncAccountAction?
    @State private var confirmsSignOut = false

    var body: some View {
        Section {
            LabeledContent("Account") {
                Text(verbatim: sync.configuration.email ?? "")
            }
            LabeledContent("Server") {
                Text(verbatim: sync.configuration.server?.displayName ?? "")
            }
            LabeledContent("Status") {
                SyncStatusText(sync: sync)
            }
            ForEach(warnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            HStack {
                Menu("Manage Account") {
                    Button("Change Master Password…") { action = .changePassword }
                    Button("New Recovery Kit…") { action = .newRecoveryKit }
                    Button("Change Email…") { action = .changeEmail }
                    Divider()
                    Button("Sign Out…") { confirmsSignOut = true }
                    Button("Delete Account…", role: .destructive) { action = .deleteAccount }
                }
                .fixedSize()
                .accessibilityIdentifier("syncAccountMenu")
                Spacer()
                Button("Sync Now") {
                    Task { await sync.coordinator?.syncNow() }
                }
                .disabled(sync.coordinator?.status == .syncing)
                .accessibilityIdentifier("syncNowButton")
            }
        } header: {
            Text("Account")
        }
        // A new kit is shown once the operation's sheet is gone: one sheet at a time (review SY12).
        .sheet(item: $action, onDismiss: showPendingKit) { action in
            SyncAccountActionSheet(sync: sync, action: action)
        }
        .confirmationDialog("Sign out of sync?", isPresented: $confirmsSignOut) {
            Button("Sign Out") {
                Task { await sync.signOut() }
            }
        } message: {
            Text("Your tabs, Spaces and settings stay on this Mac. They no longer sync with your other Macs.")
        }
    }

    private func showPendingKit() {
        if let kit = sync.pendingRecoveryKit {
            showKit(kit)
        }
    }

    /// What the user should know: refused records, full account, clocks (`SyncWarnings`).
    private var warnings: [String] {
        SyncWarnings.list(
            state: sync.engineState,
            isRecoveryKitUnsaved: sync.configuration.isRecoveryKitUnsaved,
            hasPendingKit: sync.pendingRecoveryKit != nil,
            clockOffset: sync.clockOffset,
        )
    }
}
