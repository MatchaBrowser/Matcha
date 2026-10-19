import Foundation
import Observation
import OSLog

/// Direction of a find in the page.
nonisolated enum FindDirection: Equatable, Sendable {
    case forward
    case backward
}

/// Result of the last search: nothing to report, a match found (and selected), or none.
nonisolated enum FindStatus: Equatable, Sendable {
    case idle
    case found
    case notFound
}

/// What searches in a page: the tab and its web view (`BrowserTab+Find`), a fake in the tests.
@MainActor
protocol FindPerformer: AnyObject {
    /// Searches for `query` case-insensitively, wrapping around to the start at the end. True if a match is found
    /// (it is then selected and shown); nil if the page cannot search (no web view).
    func search(_ query: String, direction: FindDirection) async -> Bool?
    /// Deselects the match found.
    func deselectMatch()
}

/// Find in a page (task 5.3): bar open or not, searched text, result. Each page has its own (tab, peek, mini
/// window): it stays with its page as you switch tabs and is found unchanged when you come back.
///
/// Typing starts the search 150 ms after the last keystroke; a more recent keystroke cancels it. Return, ⌘G and
/// ⇧⌘G search right away. WebKit keeps the selected match when the text grows longer (“p”, “po”) and moves to the
/// next one for the same text. The searched text is never logged.
@MainActor
@Observable
final class FindSession {
    typealias Sleep = @MainActor (Duration) async throws -> Void

    /// Wait after a keystroke.
    nonisolated static let typingDelay = Duration.milliseconds(150)

    private(set) var isPresented = false
    private(set) var query = ""
    /// `!query.isEmpty`, tracked separately: the menu (⌘G, ⇧⌘G) is not recomputed at each keystroke.
    private(set) var hasQuery = false
    private(set) var status = FindStatus.idle
    /// Incremented at each ⌘F: the field takes keyboard focus and selects its text.
    private(set) var focusRequest = 0

    /// Page to search in; the tab that owns the search.
    @ObservationIgnored weak var performer: (any FindPerformer)?
    @ObservationIgnored private let sleep: Sleep
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    /// Last keyboard request served by the field: a recreated field (back on the tab) does not take keyboard focus
    /// back from the page.
    @ObservationIgnored private var servedFocusRequest = 0
    /// A search selected a match: closing deselects it.
    @ObservationIgnored private var hasSelectedMatch = false

    /// `sleep` is replaced in the tests.
    init(sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    // MARK: Bar

    /// ⌘F: opens the bar, or keeps it open; in both cases, the field takes keyboard focus and selects its text (the
    /// last text searched in this page).
    func present() {
        if !isPresented {
            isPresented = true
            Logger.browser.debug("Find in page opened")
        }
        focusRequest += 1
    }

    /// True only once per keyboard request (`present`): it is up to the field to take it.
    func takeFocusRequest() -> Bool {
        guard servedFocusRequest != focusRequest else {
            return false
        }
        servedFocusRequest = focusRequest
        return true
    }

    /// ⎋ and ×: the bar closes, the pending search is cancelled and the match found is deselected. The text stays
    /// for ⌘G and the next opening.
    func close() {
        guard isPresented else {
            return
        }
        cancelSearch()
        isPresented = false
        status = .idle
        if hasSelectedMatch {
            hasSelectedMatch = false
            performer?.deselectMatch()
        }
        Logger.browser.debug("Find in page closed")
    }

    /// Page released (tab unloaded, peek or mini window closed): everything is forgotten, without touching the page.
    func reset() {
        cancelSearch()
        isPresented = false
        setQuery("")
        status = .idle
        hasSelectedMatch = false
    }

    /// The page changed address: the last result no longer holds. The bar and its text stay.
    func pageDidChange() {
        status = .idle
        hasSelectedMatch = false
    }

    /// The page's process stopped (task 5.7): the pending search is cancelled and the result forgotten, without
    /// asking anything of the page (there is no selected match anymore). The bar and its text stay: ⌘G searches
    /// again in the reloaded page.
    func pageDidTerminate() {
        cancelSearch()
        pageDidChange()
    }

    // MARK: Search

    /// New text of the field: searched forward after `typingDelay`, unless it is empty.
    func updateQuery(_ text: String) {
        guard text != query else {
            return
        }
        setQuery(text)
        cancelSearch()
        guard !text.isEmpty else {
            status = .idle
            return
        }
        searchTask = Task { [weak self, sleep] in
            do {
                try await sleep(Self.typingDelay)
            } catch {
                return
            }
            guard !Task.isCancelled else {
                return
            }
            await self?.perform(text, direction: .forward)
        }
    }

    /// ⌘E: the text selected in the page becomes the searched text, without searching (⌘G then finds the next one);
    /// an open bar shows it.
    func useSelection(_ text: String) {
        guard !text.isEmpty else {
            return
        }
        cancelSearch()
        setQuery(text)
        status = .idle
    }

    /// Return, ⌘G, ⌄ button: next match.
    func findNext() {
        search(.forward)
    }

    /// ⇧Return, ⇧⌘G, ⌃ button: previous match.
    func findPrevious() {
        search(.backward)
    }

    /// Tests: waits for the end of the current search.
    func waitForPendingSearch() async {
        await searchTask?.value
    }

    /// Searches right away (the pending keystroke is cancelled); if the bar is closed (⌘G), it opens without taking
    /// keyboard focus. Nothing without text.
    private func search(_ direction: FindDirection) {
        guard !query.isEmpty else {
            return
        }
        isPresented = true
        cancelSearch()
        let text = query
        searchTask = Task { [weak self] in
            await self?.perform(text, direction: direction)
        }
    }

    /// Result ignored if another search has taken over, if the text has changed or if the bar is closed.
    private func perform(_ text: String, direction: FindDirection) async {
        let found = await performer?.search(text, direction: direction)
        guard !Task.isCancelled, text == query, isPresented else {
            return
        }
        switch found {
        case .some(true):
            status = .found
            hasSelectedMatch = true
        case .some(false):
            status = .notFound
        case nil:
            status = .idle
        }
    }

    private func setQuery(_ text: String) {
        query = text
        if hasQuery == text.isEmpty {
            hasQuery = !text.isEmpty
        }
    }

    private func cancelSearch() {
        searchTask?.cancel()
        searchTask = nil
    }
}
