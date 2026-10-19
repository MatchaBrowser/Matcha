import SwiftUI

/// Private browser window: its own session, in memory, forgotten when the window closes. Its finished downloads stay
/// in Downloads but leave the list; those in progress are cancelled. Its sign-in windows (task 5.8) close with it.
struct PrivateWindowView: View {
    @State private var session = BrowserSession.makePrivate()
    @Environment(DownloadManager.self) private var downloads

    var body: some View {
        BrowserWindowView(session: session)
            .onDisappear {
                session.popupWindows.closeAll()
                downloads.forgetDownloads(in: session.downloadScope)
            }
    }
}
