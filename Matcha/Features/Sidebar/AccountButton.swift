import SwiftUI

/// Circle at the bottom right of the sidebar (task 7.9), in place of the “+”: the sync account's avatar, in a ring
/// whose color gives the state of sync. Its menu creates a Space, shows the state of sync, syncs now, and opens
/// Settings > Sync.
struct AccountButton: View {
    let newSpace: () -> Void

    @Environment(SyncService.self) private var sync
    @Environment(SettingsSelection.self) private var settingsSelection
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Menu {
            Button("New Space", systemImage: "plus", action: newSpace)
                .accessibilityIdentifier("newSpaceMenuItem")
            Divider()
            Text(status)
            if sync.isActive {
                Button("Sync Now", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await sync.coordinator?.syncNow() }
                }
                .disabled(sync.coordinator?.status == .syncing)
            }
            Button(sync.isActive ? "Sync Settings…" : "Turn On Sync…", systemImage: "gearshape", action: openSyncSettings)
            if sync.supportsAvatar {
                Button("Change Avatar…", systemImage: "person.crop.circle", action: openSyncSettings)
            }
        } label: {
            AccountAvatarView(image: sync.avatar, size: 17)
                .padding(2.5)
                .overlay(Circle().strokeBorder(ringColor, lineWidth: 1.5))
                .frame(width: SidebarIconButtonStyle.size, height: SidebarIconButtonStyle.size)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text(status))
        .accessibilityLabel(Text("Account and Sync"))
        .accessibilityValue(Text(status))
        .accessibilityIdentifier("accountButton")
    }

    /// Gray without sync, green while it works (a sync in progress included), red after a failed sync or when this Mac
    /// was signed out of its account.
    private var ringColor: Color {
        guard let coordinator = sync.coordinator else {
            return sync.configuration.signedOutReason == nil ? .gray : .red
        }
        return coordinator.status == .failed ? .red : .green
    }

    private var status: LocalizedStringKey {
        guard let coordinator = sync.coordinator else {
            return sync.configuration.signedOutReason == nil ? "Sync is off" : "Sync: sign in again"
        }
        switch coordinator.status {
        case .syncing: return "Syncing…"
        case .failed: return "Sync failed"
        case .idle: return coordinator.lastSyncDate == nil ? "Sync is on" : "Synced"
        }
    }

    private func openSyncSettings() {
        settingsSelection.tab = .sync
        openSettings()
    }
}
