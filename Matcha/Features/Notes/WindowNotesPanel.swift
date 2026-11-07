import SwiftUI

/// The notes panel in a browser window (task 12.3): its width, shared by the windows and changed by its handle, and
/// the same margins as the card.
struct WindowNotesPanel: View {
    let model: NotesPanelModel
    /// Margins of the card, without the one shared with it.
    let paddingEdges: Edge.Set

    @AppStorage(NotesPanelMetrics.widthKey) private var width = NotesPanelMetrics.defaultWidth
    /// Width during a drag of the handle, for this window only.
    @State private var liveWidth: Double?

    var body: some View {
        NotesPanel(model: model)
            .frame(width: NotesPanelMetrics.clampedWidth(liveWidth ?? width))
            .overlay(alignment: .leading) {
                NotesPanelResizeHandle(width: $width, liveWidth: $liveWidth)
                    .offset(x: -NotesPanelResizeHandle.thickness)
            }
            .padding(paddingEdges, BrowserWindowView.cardMargin)
    }
}

extension View {
    /// The window's notes panel follows the selected tab and its page; it closes when another tab is selected,
    /// unless the settings keep it open.
    func followsPageForNotes(_ model: WindowModel) -> some View {
        modifier(NotesPanelTracking(model: model))
    }
}

private struct NotesPanelTracking: ViewModifier {
    let model: WindowModel

    @AppStorage(BrowserSettings.Key.keepsNotesPanelOpen) private var keepsOpen = BrowserSettings.keepsNotesPanelOpen

    /// What the panel reads from the page: its document and its title.
    private struct Page: Equatable {
        let url: URL?
        let title: String?
    }

    func body(content: Content) -> some View {
        let tab = model.selectedTab
        content
            .onChange(of: Page(url: tab?.documentURL, title: tab?.title), initial: true) { _, page in
                model.notesPanel.show(page: page.url, title: page.title)
            }
            .onChange(of: tab?.id) {
                withMotion(.easeInOut(duration: 0.2)) { model.notesPanel.selectedTabDidChange(keepsOpen: keepsOpen) }
            }
    }
}
