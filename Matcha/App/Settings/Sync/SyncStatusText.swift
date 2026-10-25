import SwiftUI

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
