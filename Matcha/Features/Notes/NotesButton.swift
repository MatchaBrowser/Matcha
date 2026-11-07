import SwiftUI

/// Button next to the address of a page (task 12.3): shows or hides the window's notes panel. Filled when the page or
/// its site has a note. Absent from a private window and outside the web (no note can be linked there).
struct NotesButton: View {
    /// Page described: the selected tab, or the tab of this pane of a split (a click in its bar activates it first).
    let tab: BrowserTab?

    @Environment(WindowModel.self) private var windowModel: WindowModel?

    var body: some View {
        if let windowModel, let url = tab?.documentURL, SiteOrigin.web(of: url) != nil, windowModel.notesPanel.isAvailable {
            let panel = windowModel.notesPanel
            let hasNote = panel.store.note(linkedTo: url, profileID: windowModel.space.record.profile?.id) != nil
            Button {
                withMotion(.easeInOut(duration: 0.2)) { panel.toggle() }
            } label: {
                Label(title(hasNote: hasNote), systemImage: hasNote ? "doc.text.fill" : "doc.text")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(SidebarIconButtonStyle())
            .foregroundStyle(hasNote ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(panel.isOpen ? 0.12 : 0)))
            .help(title(hasNote: hasNote))
            .accessibilityAddTraits(panel.isOpen ? .isSelected : [])
            .accessibilityIdentifier("notesButton")
            .transition(.opacity)
        }
    }

    private func title(hasNote: Bool) -> String {
        hasNote
            ? String(localized: "Show Note", comment: "Button next to the address of a page that has a note; opens the notes panel")
            : String(localized: "Add a Note", comment: "Button next to the address of a page without a note; opens the notes panel")
    }
}
