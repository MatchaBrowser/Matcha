import SwiftUI

/// History window (⌘Y, History menu): the visits of the profile of the Space displayed by the main window. A single
/// window, opened only by the user, never restored at launch.
struct HistoryWindow: View {
    let session: BrowserSession
    @Environment(MiniWindowManager.self) private var miniWindows

    var body: some View {
        if let store = session.history {
            HistoryContent(store: store, session: session, miniWindows: miniWindows)
        }
    }
}

/// Content of the window: its model follows the profile shown.
private struct HistoryContent: View {
    let session: BrowserSession
    let miniWindows: MiniWindowManager
    @State private var model: HistoryWindowModel
    @Environment(\.openWindow) private var openWindow

    init(store: HistoryStore, session: BrowserSession, miniWindows: MiniWindowManager) {
        self.session = session
        self.miniWindows = miniWindows
        _model = State(initialValue: HistoryWindowModel(store: store, profileID: miniWindows.historyProfile?.id))
    }

    /// Profile shown.
    private var profile: ProfileRecord? {
        miniWindows.historyProfile
    }

    /// Name of the profile shown when there are several: the window's subtitle and the clearing dialog's message.
    private var profileName: String? {
        session.profiles.count > 1 ? profile?.name : nil
    }

    var body: some View {
        // Navigation container: the search goes into the window's toolbar.
        NavigationStack {
            HistoryView(model: model, faviconService: session.faviconService, profileName: profileName, open: open)
                .navigationTitle(Text("History"))
                .navigationSubtitle(profileName ?? "")
        }
        .onChange(of: profile?.id) { _, id in model.profileID = id }
        .frame(minWidth: 480, minHeight: 320)
    }

    /// Double-click, Return, “Open in New Tab”: each row in a new tab of the main window, which comes to the front
    /// (reopened if needed, like “Open in Space”).
    private func open(_ rows: [HistoryRow]) {
        miniWindows.openFromHistory(rows.map(\.url), profileID: model.profileID) {
            openWindow(id: MatchaApp.browserWindowID)
        }
    }
}
