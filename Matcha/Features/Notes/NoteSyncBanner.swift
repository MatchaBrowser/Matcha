import SwiftUI

/// Above a note too long to go to the other Macs (task 12.8): it stays on this one.
struct NoteSyncBanner: View {
    let note: NoteSummary

    var body: some View {
        if note.isTooLargeToSync {
            Text(
                "This note is too long to be synced to your other Macs. It stays on this Mac.",
                comment: "Banner above a note larger than sync takes",
            )
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.15))
        }
    }
}
