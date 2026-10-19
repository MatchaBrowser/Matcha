import SwiftUI

/// Private browser window: its own session, in memory, forgotten when the window closes. Its finished downloads stay
/// in Downloads but leave the list; those in progress are cancelled. Its sign-in windows (task 5.8) close with it.
struct PrivateWindowView: View {
    /// Made once, when the window first shows (a new view value doesn't make another session, audit R5).
    @State private var holder = PrivateSessionHolder()
    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        let session = holder.session
        BrowserWindowView(session: session)
            .onDisappear {
                session.popupWindows.closeAll()
                downloads.forgetDownloads(in: session.downloadScope)
            }
    }
}
