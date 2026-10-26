import Foundation

/// Visits of a page (tab, Peek, mini window page), task 5.5. The page keeps its last visit to extend it (reload
/// shortly after), give it a title that arrives late, and count the addresses the page changes itself (History
/// API: `pushState`, `replaceState`). Rules: `HistoryRecordingPolicy`. Nothing is kept without a `HistoryScope`
/// (private window).
@MainActor
final class PageHistory {
    /// Followed page: its address, title and loading state are read again before keeping an address change.
    weak var page: BrowserTab?
    /// Wait before keeping an address changed by the page; shortened in tests.
    var sameDocumentDelay = HistoryRecordingPolicy.sameDocumentDelay
    /// How that wait passes; replaced in tests, which then decide when it has passed (review TS16).
    var sleep: @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

    private var scope: HistoryScope?
    private var lastVisit: HistoryRecordingPolicy.PageVisit?
    private var lastVisitHasTitle = false
    /// Address of the last loaded document: an address change without loading must stay on its origin.
    private var loadedURL: URL?
    /// Key of the page reloaded when waking from sleep (task 5.6): its next load is not a visit.
    private var resumedURLKey: String?
    private var pendingChange: Task<Void, Never>?
    /// Documents finished loading (`pageDidFinishLoading`), recorded or not: what the tests wait for rather than a
    /// fixed time (review TS2).
    private(set) var finishedLoads = 0

    /// True while an address changed by the page waits `sameDocumentDelay` (tests).
    var hasPendingChange: Bool {
        pendingChange != nil
    }

    /// A document has finished loading in the page (`didFinish` of the main frame).
    func pageDidFinishLoading(url: URL?, title: String?, scope: HistoryScope?) {
        finishedLoads += 1
        cancelPendingChange()
        self.scope = scope
        loadedURL = url
        let resumedKey = resumedURLKey
        resumedURLKey = nil
        if let resumedKey, HistoryRecordingPolicy.storedURL(for: url).map(CommandText.urlKey) == resumedKey {
            return
        }
        record(url: url, title: title)
    }

    /// The page wakes from sleep and is about to reload `url` (task 5.6): this reload, which the user did not ask
    /// for, is not a new visit. Another address loaded first is one.
    func pageWillResume(url: URL?) {
        resumedURLKey = HistoryRecordingPolicy.storedURL(for: url).map(CommandText.urlKey)
    }

    /// Load failed or interrupted: a pending changed address is not kept.
    func navigationDidFail() {
        cancelPendingChange()
        resumedURLKey = nil
    }

    /// The page's address has changed. With no load in progress, it is the page itself: the address is kept if it
    /// lasts `sameDocumentDelay` (only the last of a burst counts). A fragment alone does not change the key.
    func urlDidChange(to url: URL?, isLoading: Bool) {
        cancelPendingChange()
        guard !isLoading, scope != nil, let url, let stored = HistoryRecordingPolicy.storedURL(for: url),
              CommandText.urlKey(stored) != lastVisit?.urlKey,
              HistoryRecordingPolicy.isSameDocumentChange(from: loadedURL, to: url)
        else {
            return
        }
        let delay = sameDocumentDelay
        let sleep = sleep
        pendingChange = Task { [weak self] in
            try? await sleep(delay)
            guard !Task.isCancelled, let self else {
                return
            }
            pendingChange = nil
            if let page, !page.isLoading, page.url == url {
                record(url: url, title: page.title)
            }
        }
    }

    /// The page's title has changed: it renames the last visit if it arrives shortly after it, at the same address,
    /// or if the visit did not have a title yet.
    func titleDidChange(to title: String?, pageURL: URL?) {
        guard let scope, let lastVisit, let title = HistoryRecordingPolicy.normalizedTitle(title) else {
            return
        }
        let pageKey = HistoryRecordingPolicy.storedURL(for: pageURL).map(CommandText.urlKey)
        guard HistoryRecordingPolicy.acceptsTitle(
            for: lastVisit,
            visitHasTitle: lastVisitHasTitle,
            pageURLKey: pageKey,
            now: scope.store.now(),
        ) else {
            return
        }
        scope.store.setTitle(title, ofVisit: lastVisit.id, profileID: scope.profileID)
        lastVisitHasTitle = true
    }

    /// Page released (tab unloaded, mini window closed): everything is forgotten.
    func reset() {
        cancelPendingChange()
        scope = nil
        lastVisit = nil
        lastVisitHasTitle = false
        loadedURL = nil
        resumedURLKey = nil
    }

    private func record(url: URL?, title: String?) {
        guard let scope, let stored = HistoryRecordingPolicy.storedURL(for: url) else {
            return
        }
        let key = CommandText.urlKey(stored)
        let title = HistoryRecordingPolicy.normalizedTitle(title)
        let now = scope.store.now()
        let decision = HistoryRecordingPolicy.decision(previous: lastVisit, urlKey: key, now: now)
        if decision == .refresh, let lastVisit, scope.store.refreshVisit(lastVisit.id, title: title, profileID: scope.profileID) {
            self.lastVisit = .init(id: lastVisit.id, urlKey: key, date: now)
            lastVisitHasTitle = lastVisitHasTitle || title != nil
            return
        }
        let visit = scope.store.recordVisit(url: stored, title: title, profileID: scope.profileID, spaceID: scope.spaceID)
        lastVisit = .init(id: visit.id, urlKey: visit.urlKey, date: visit.date)
        lastVisitHasTitle = visit.title != nil
    }

    private func cancelPendingChange() {
        pendingChange?.cancel()
        pendingChange = nil
    }
}
