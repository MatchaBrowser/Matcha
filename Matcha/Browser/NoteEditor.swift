import Foundation
import Observation
import OSLog
import WebKit

/// Editor of one note at a time (task 12.2): OpenBlock in a web view of its own, which shows only the app's page
/// (`NoteEditorResources`), with no extension, blocker, website data or network. The page sends the document a moment
/// after each change, and at once when the app asks for it (`flush`, before another note or closing); it goes to the
/// store (`NoteStore.setContent`). One editor is kept from one note to the next: a new note doesn't reload the page.
@MainActor
@Observable
final class NoteEditor {
    enum State: Equatable, Sendable {
        /// No note: none given, or it was deleted.
        case empty
        /// The page is loading, or the note is on its way.
        case loading
        case editing
        /// The document has blocks this version doesn't know: shown read-only, never saved (`SYNC.md` § 2.10).
        case unreadable
        /// The document grew beyond what the store takes: the page keeps it, but it isn't saved until it shrinks.
        case tooLarge
    }

    private(set) var state = State.empty
    private(set) var noteID: UUID?
    @ObservationIgnored let webView: WKWebView
    /// Opens a link of the note (http or https) in the browser; nil: nothing happens.
    @ObservationIgnored var openLink: (@MainActor (URL) -> Void)?
    @ObservationIgnored private let store: NoteStore
    @ObservationIgnored private let texts: [String: String]
    @ObservationIgnored private let delegate: NoteEditorDelegate
    @ObservationIgnored private var isPageReady = false
    /// Note of each document given to the page, by token: a change of the previous note still on its way goes to it.
    @ObservationIgnored private var tokens: [String: UUID] = [:]
    @ObservationIgnored private var tokenOrder: [String] = []
    @ObservationIgnored private var currentToken: String?
    /// Latest call to `open`: an earlier one that is still waiting for its `flush` gives way.
    @ObservationIgnored private var openRequest = 0

    init(store: NoteStore, texts: [String: String] = NoteEditorTexts.current, bundle: Bundle = .main) {
        self.store = store
        self.texts = texts
        let delegate = NoteEditorDelegate()
        self.delegate = delegate
        webView = WKWebView(frame: .zero, configuration: Self.configuration(handler: delegate, bundle: bundle))
        webView.navigationDelegate = delegate
        webView.uiDelegate = delegate
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = false
        #if DEBUG
            webView.isInspectable = true
        #endif
        delegate.editor = self
        loadPage()
    }

    /// A web view freed off the main thread would crash WebKit.
    isolated deinit {}

    /// Shows the note `id` (nil: none), after saving the one shown.
    func open(_ id: UUID?) async {
        openRequest += 1
        let request = openRequest
        await flush()
        guard request == openRequest else {
            return
        }
        // A deleted note: nothing to wait for.
        let exists = id.map { id in store.notes.contains { $0.id == id } } ?? false
        noteID = exists ? id : nil
        currentToken = nil
        state = exists ? .loading : .empty
        sendDocument()
    }

    /// Saves the document shown now, if it changed since the page last sent it.
    func flush() async {
        guard isPageReady, currentToken != nil else {
            return
        }
        do {
            let result = try await webView.callAsyncJavaScript(
                NoteEditorScript.flushBody,
                arguments: ["bridge": NoteEditorScript.bridgeName],
                in: nil,
                contentWorld: NoteEditorScript.world,
            )
            if let message = NoteEditorMessage(body: result) {
                receive(message)
            }
        } catch {
            Logger.notes.error("Note not flushed: \(error.logSummary, privacy: .public)")
        }
    }

    /// Shows again the note's document as saved (it was changed elsewhere: a quote added), after saving what the page
    /// had.
    func refresh() async {
        await flush()
        guard noteID != nil else {
            return
        }
        currentToken = nil
        sendDocument()
    }

    /// A message of the page's bridge (`NoteEditorDelegate`).
    func receive(_ message: NoteEditorMessage) {
        switch message {
        case .ready:
            isPageReady = true
            sendDocument()
        case let .change(token, content):
            save(content, token: token)
        case let .unreadable(token):
            if token == currentToken {
                state = .unreadable
                Logger.notes.notice("Note unreadable by this version: shown read-only")
            }
        case let .tooLarge(token):
            if token == currentToken {
                state = .tooLarge
            }
        }
    }

    /// The page's process stopped: the page comes back, then the note as last saved.
    func pageDidTerminate() {
        Logger.notes.notice("Note editor page stopped: reloaded")
        isPageReady = false
        currentToken = nil
        state = noteID == nil ? .empty : .loading
        loadPage()
    }

    private func loadPage() {
        guard let url = URL(string: NoteEditorResources.pageAddress) else {
            return
        }
        webView.load(URLRequest(url: url))
    }

    private func save(_ content: String, token: String) {
        guard let id = tokens[token] else {
            return
        }
        let result = store.setContent(content, of: id)
        guard token == currentToken else {
            return
        }
        switch result {
        case .tooLarge: state = .tooLarge
        case .saved, .unchanged: state = .editing
        case .notFound: state = .empty
        }
    }

    /// Gives the page the note shown, once the page is ready.
    private func sendDocument() {
        guard isPageReady, let id = noteID else {
            return
        }
        guard let content = store.content(of: id) else {
            noteID = nil
            state = .empty
            return
        }
        let token = UUID().uuidString
        remember(token, for: id)
        currentToken = token
        guard let payload = NoteEditorPayload(token: token, content: content, editable: true, texts: texts).json else {
            return
        }
        state = .editing
        webView.callAsyncJavaScript(
            NoteEditorScript.loadBody,
            arguments: ["bridge": NoteEditorScript.bridgeName, "payload": payload],
            in: nil,
            in: NoteEditorScript.world,
        ) { result in
            if case let .failure(error) = result {
                Logger.notes.error("Note not given to the editor: \(error.logSummary, privacy: .public)")
            }
        }
    }

    /// The last few tokens are enough: a change arrives within a moment of the next note.
    private func remember(_ token: String, for id: UUID) {
        tokens[token] = id
        tokenOrder.append(token)
        while tokenOrder.count > 8 {
            tokens[tokenOrder.removeFirst()] = nil
        }
    }

    private static func configuration(handler: NoteEditorDelegate, bundle: Bundle) -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(NoteEditorSchemeHandler(bundle: bundle), forURLScheme: NoteEditorResources.scheme)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        NoteEditorScript.install(in: configuration.userContentController, handler: handler)
        return configuration
    }
}
