import Foundation

/// Visites d'une page (onglet, aperçu, page d'une mini-fenêtre), tâche 5.5. La page retient sa dernière visite pour
/// la prolonger (rechargement peu après), lui donner un titre arrivé tard, et compter les adresses que la page change
/// elle-même (History API : `pushState`, `replaceState`). Règles : `HistoryRecordingPolicy`. Rien n'est retenu sans
/// `HistoryScope` (fenêtre privée).
@MainActor
final class PageHistory {
    /// Page suivie : son adresse, son titre et son chargement sont relus avant de retenir un changement d'adresse.
    weak var page: BrowserTab?
    /// Attente avant de retenir une adresse changée par la page ; raccourcie dans les tests.
    var sameDocumentDelay = HistoryRecordingPolicy.sameDocumentDelay

    private var scope: HistoryScope?
    private var lastVisit: HistoryRecordingPolicy.PageVisit?
    private var lastVisitHasTitle = false
    /// Adresse du dernier document chargé : un changement d'adresse sans chargement doit rester sur son origine.
    private var loadedURL: URL?
    /// Clé de la page rechargée par la sortie de veille (tâche 5.6) : son prochain chargement n'est pas une visite.
    private var resumedURLKey: String?
    private var pendingChange: Task<Void, Never>?

    /// Un document a fini de se charger dans la page (`didFinish` du cadre principal).
    func pageDidFinishLoading(url: URL?, title: String?, scope: HistoryScope?) {
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

    /// La page sort de veille et va recharger `url` (tâche 5.6) : ce rechargement, que l'utilisateur n'a pas demandé,
    /// n'est pas une nouvelle visite. Une autre adresse chargée d'abord en est une.
    func pageWillResume(url: URL?) {
        resumedURLKey = HistoryRecordingPolicy.storedURL(for: url).map(CommandText.urlKey)
    }

    /// Chargement échoué ou interrompu : une adresse changée en attente n'est pas retenue.
    func navigationDidFail() {
        cancelPendingChange()
        resumedURLKey = nil
    }

    /// L'adresse de la page a changé. Sans chargement en cours, c'est la page elle-même : l'adresse est retenue si
    /// elle tient `sameDocumentDelay` (seule la dernière d'une rafale compte). Un fragment seul ne change pas la clé.
    func urlDidChange(to url: URL?, isLoading: Bool) {
        cancelPendingChange()
        guard !isLoading, scope != nil, let url, let stored = HistoryRecordingPolicy.storedURL(for: url),
              CommandText.urlKey(stored) != lastVisit?.urlKey,
              HistoryRecordingPolicy.isSameDocumentChange(from: loadedURL, to: url)
        else {
            return
        }
        let delay = sameDocumentDelay
        pendingChange = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, let page, !page.isLoading, page.url == url else {
                return
            }
            record(url: url, title: page.title)
        }
    }

    /// Le titre de la page a changé : il renomme la dernière visite s'il arrive peu après elle, à la même adresse, ou
    /// si elle n'avait pas encore de titre.
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

    /// Page libérée (onglet déchargé, mini-fenêtre fermée) : tout est oublié.
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
