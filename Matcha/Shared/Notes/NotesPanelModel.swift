import Foundation
import Observation

/// Notes panel of a window (task 12.3): the note of the page shown, to the right of the card. It follows the selected
/// tab (the active pane of a split) and its document (`documentURL`, TR1): the page's own note, otherwise its site's.
/// Its editor (`NoteEditor`, one web view) is made when the panel opens, kept from one page to the next, and freed
/// when it closes, after the note is saved. A private window has no notes: the panel isn't offered there.
@MainActor
@Observable
final class NotesPanelModel {
    private(set) var isOpen = false
    /// Document of the page shown, and its title (the title of a new note).
    private(set) var page: URL?
    private(set) var pageTitle: String?
    private(set) var editor: NoteEditor?
    @ObservationIgnored let store: NoteStore
    /// Profile of the Space shown: notes belong to a profile. Given by the window once it is made.
    @ObservationIgnored var profileID: @MainActor () -> UUID? = { nil }
    /// Makes the editor; replaced by the tests.
    @ObservationIgnored private let makeEditor: @MainActor (NoteStore) -> NoteEditor

    init(store: NoteStore, makeEditor: @escaping @MainActor (NoteStore) -> NoteEditor = { NoteEditor(store: $0) }) {
        self.store = store
        self.makeEditor = makeEditor
    }

    /// False in a private window: no note is kept there.
    var isAvailable: Bool {
        store.isPersistent
    }

    /// Note of the page shown: its own, otherwise its site's; nil without one.
    var note: NoteSummary? {
        page.flatMap { store.note(linkedTo: $0, profileID: profileID()) }
    }

    /// The page shown is a website (http or https): a note can be linked to it.
    var canLink: Bool {
        page.flatMap { SiteOrigin.web(of: $0) } != nil
    }

    /// Site of the page shown, as a site note names it (“example.com”); nil outside the web.
    var site: String? {
        page.flatMap { NoteLink.key(for: $0, scope: .site) }
    }

    func open() {
        guard isAvailable, !isOpen else {
            return
        }
        isOpen = true
        if editor == nil {
            editor = makeEditor(store)
        }
        showNote()
    }

    /// Hides the panel; its note is saved, then its editor freed.
    func close() {
        guard isOpen else {
            return
        }
        isOpen = false
        let editor = editor
        self.editor = nil
        Task { await editor?.flush() }
    }

    func toggle() {
        if isOpen {
            close()
        } else {
            open()
        }
    }

    /// The window shows another page (another tab, a navigation, another Space).
    func show(page: URL?, title: String?) {
        self.page = page
        pageTitle = title.flatMap { $0.isEmpty ? nil : $0 }
        showNote()
    }

    /// Another tab is selected: the panel closes, unless the settings keep it open.
    func selectedTabDidChange(keepsOpen: Bool) {
        if !keepsOpen {
            close()
        }
    }

    /// Makes the note of the page shown, for this page or its whole site, titled like the page.
    func createNote(scope: NoteLinkScope) {
        guard let page, let link = NoteLink(url: page, scope: scope, title: pageTitle) else {
            return
        }
        store.createNote(profileID: profileID(), title: pageTitle ?? "", link: link)
        showNote()
    }

    /// Links the note shown to this page only, or to its whole site.
    func setScope(_ scope: NoteLinkScope) {
        guard let note, note.link?.scope != scope, let page, let link = NoteLink(url: page, scope: scope, title: pageTitle) else {
            return
        }
        store.setLink(link, of: note.id)
        showNote()
    }

    /// The note shown leaves its page: it stays in the library, in its folder.
    func detachNote() {
        guard let note else {
            return
        }
        store.setLink(nil, of: note.id)
        showNote()
    }

    func deleteNote() {
        guard let note else {
            return
        }
        store.delete(note.id)
        showNote()
    }

    /// Gives the editor the note of the page shown, if it changed (also after a change made elsewhere: the view calls
    /// it when `note` changes).
    func showNote() {
        guard isOpen, let editor else {
            return
        }
        let id = note?.id
        guard editor.noteID != id else {
            return
        }
        Task { await editor.open(id) }
    }
}

/// “Add to Note” in the menu of a selection (task 12.6): the passage goes to the page's note (its own, otherwise its
/// site's; a new page note if there is none), and the panel opens on it.
extension NotesPanelModel: NoteQuoteReceiving {
    var acceptsQuotes: Bool {
        isAvailable
    }

    func addQuote(_ passage: String, from page: URL, title: String?) {
        Task { await quote(passage, from: page, title: title) }
    }

    func quote(_ passage: String, from page: URL, title: String?) async {
        let title = title.flatMap { $0.isEmpty ? nil : $0 }
        guard isAvailable, let link = NoteLink(url: page, scope: .page, title: title) else {
            return
        }
        let profileID = profileID()
        guard let id = store.note(linkedTo: page, profileID: profileID)?.id
            ?? store.createNote(profileID: profileID, title: title ?? "", link: link)?.id
        else {
            return
        }
        // The editor may hold changes not saved yet: they go first.
        if editor?.noteID == id {
            await editor?.flush()
        }
        guard let content = store.content(of: id),
              let updated = NoteQuote.appending(
                  passage,
                  source: NoteQuote.fragmentURL(for: NoteQuote.cleaned(passage), in: page),
                  sourceTitle: title ?? AddressDisplay.short(for: page),
                  to: content,
              )
        else {
            return
        }
        store.setContent(updated, of: id)
        open()
        if editor?.noteID == id {
            await editor?.refresh()
        }
    }
}
