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

    /// What the user should know: refused records, full account, clocks.
    private var warnings: [String] {
        var warnings: [String] = []
        if let state = sync.engineState {
            let tooLarge = state.rejected.values.count { $0.code == SyncRejectionCode.payloadTooLarge }
            if tooLarge > 0 {
                warnings.append(String(localized: "\(tooLarge) items are too big to sync."))
            }
            if state.isQuotaExceeded {
                warnings.append(String(localized: "The account's space is full: new changes wait on this Mac."))
            }
            if sync.configuration.isRecoveryKitUnsaved, sync.pendingRecoveryKit == nil {
                warnings.append(String(
                    localized: "Your recovery kit wasn't saved: make a new one in Manage Account.",
                    comment: "Settings > Sync: warning when a new recovery key was made but its kit wasn't saved",
                ))
            }
            if state.showsFutureDateWarning() {
                warnings.append(String(localized: "The clock of one of your Macs seems to be ahead."))
            }
            if state.entries.values.contains(where: \.isUnreadable) {
                warnings.append(String(localized: "Some synced data is unreadable and was left aside."))
            }
        }
        if let offset = sync.clockOffset, abs(offset) > SyncService.clockWarningGap {
            warnings.append(offset > SyncService.maximumClockLead
                ? String(localized: "This Mac's clock is more than a day ahead: nothing is sent until it is corrected.")
                : String(localized: "This Mac's clock is off. Check the date and time in System Settings."))
        }
        return warnings
    }
}

/// “Synced 2 minutes ago”, “Syncing…”, or the last error.
struct SyncStatusText: View {
    let sync: SyncService

    var body: some View {
        if sync.coordinator?.status == .syncing {
            Text("Syncing…")
        } else if let error = sync.lastError, sync.coordinator?.status == .failed {
            Text(verbatim: SyncErrorText.message(for: error))
                .foregroundStyle(.red)
        } else if let date = sync.coordinator?.lastSyncDate {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                Text("Synced \(date.formatted(.relative(presentation: .named)))")
            }
        } else {
            Text("Waiting…", comment: "Settings > Sync: no sync done yet")
        }
    }
}
