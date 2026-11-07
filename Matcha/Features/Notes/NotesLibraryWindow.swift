import SwiftUI

/// Notes library window (task 12.4, View > Show All Notes): the notes of the profile of the Space shown by the main
/// window, like the history window. A single window, opened only by the user, never restored at launch.
struct NotesLibraryWindow: View {
    let session: BrowserSession
    @Environment(MiniWindowManager.self) private var miniWindows

    var body: some View {
        NotesLibraryContent(session: session, miniWindows: miniWindows)
    }
}

/// Content of the window: its model follows the profile shown.
private struct NotesLibraryContent: View {
    let session: BrowserSession
    let miniWindows: MiniWindowManager
    @State private var model: NotesLibraryModel
    @Environment(\.openWindow) private var openWindow

    init(session: BrowserSession, miniWindows: MiniWindowManager) {
        self.session = session
        self.miniWindows = miniWindows
        _model = State(initialValue: NotesLibraryModel(store: session.notes, profileID: miniWindows.historyProfile?.id))
    }

    /// Name of the profile shown when there are several: the window's subtitle.
    private var profileName: String? {
        session.profiles.count > 1 ? miniWindows.historyProfile?.name : nil
    }

    var body: some View {
        NavigationSplitView {
            NotesLibrarySidebar(model: model)
                .navigationSplitViewColumnWidth(min: 180, ideal: 210, max: 320)
        } content: {
            NotesLibraryList(model: model, openPage: openPage)
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
        } detail: {
            NotesLibraryDetail(model: model, openPage: openPage)
        }
        .navigationTitle(Text("Notes", comment: "Title of the notes library window"))
        .navigationSubtitle(profileName ?? "")
        .searchable(text: $model.searchText, placement: .toolbar, prompt: Text("Search Notes", comment: "Notes library: search field"))
        .onChange(of: miniWindows.historyProfile?.id) { _, id in model.profileID = id }
        // A note deleted elsewhere (panel, another window): the editor follows.
        .onChange(of: session.notes.notes.map(\.id)) { model.showSelection() }
        .onAppear {
            model.start()
            model.editor?.openLink = openPage
        }
        .onDisappear { model.stop() }
        .frame(minWidth: 720, minHeight: 420)
    }

    /// The page of a linked note, in a new tab of the main window, which comes to the front.
    private func openPage(_ url: URL) {
        miniWindows.openFromHistory([url], profileID: model.profileID) {
            openWindow(id: MatchaApp.browserWindowID)
        }
    }
}
