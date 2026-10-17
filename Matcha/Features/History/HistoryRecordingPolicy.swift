import Foundation

/// Règles de l'historique (tâche 5.5), pures : ce qui est retenu, sous quelle forme, et quand une visite en
/// prolonge une autre plutôt que d'en créer une. Voir `DECISIONS.md`.
nonisolated enum HistoryRecordingPolicy {
    /// Ce que fait une page qui vient de s'afficher à une adresse, d'après la dernière visite qu'elle a retenue.
    enum Decision: Equatable, Sendable {
        /// Nouvelle visite.
        case record
        /// Même page, même adresse, peu après : la visite précédente prend la nouvelle date et le nouveau titre
        /// (rechargements en rafale, redirection qui revient).
        case refresh
    }

    /// Dernière visite retenue par une page.
    struct PageVisit: Equatable, Sendable {
        let id: UUID
        let urlKey: String
        let date: Date
    }

    /// Une même adresse rechargée par la même page dans ce délai ne compte qu'une fois.
    static let mergeInterval: TimeInterval = 60
    /// Un titre qui change dans ce délai après la visite la renomme (titre posé par le script de la page) ; ensuite,
    /// seul un titre qui manquait encore est pris.
    static let titleUpdateInterval: TimeInterval = 5
    /// Adresse changée par la page sans nouveau document (History API) : retenue si elle tient ce délai, pour ne
    /// garder que la dernière d'une rafale de `replaceState`.
    static let sameDocumentDelay: Duration = .seconds(1)

    /// Adresse retenue, ou nil si l'adresse ne va pas dans l'historique : seulement les pages web (`http`,
    /// `https`, avec un hôte) et les fichiers locaux ; jamais `about:`, `data:`, `blob:`, `javascript:` ni les
    /// schémas d'autres apps ou de tests. Le fragment et les identifiants (`user:password@`) sont retirés.
    static func storedURL(for url: URL?) -> URL? {
        guard let url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch components.scheme?.lowercased() {
        case "http", "https":
            guard let host = components.host, !host.isEmpty else {
                return nil
            }
        case "file":
            break
        default:
            return nil
        }
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    /// Titre retenu : sans espaces aux bords, nil s'il est vide.
    static func normalizedTitle(_ title: String?) -> String? {
        guard let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }

    /// Nouvelle visite, ou rafraîchissement de `previous` si c'est la même adresse dans le délai de fusion.
    static func decision(previous: PageVisit?, urlKey: String, now: Date) -> Decision {
        guard let previous, previous.urlKey == urlKey else {
            return .record
        }
        return abs(now.timeIntervalSince(previous.date)) <= mergeInterval ? .refresh : .record
    }

    /// Vrai si un nouveau titre de la page renomme `visit` : même adresse, et titre arrivé dans le délai ou visite
    /// encore sans titre.
    static func acceptsTitle(for visit: PageVisit, visitHasTitle: Bool, pageURLKey: String?, now: Date) -> Bool {
        guard pageURLKey == visit.urlKey else {
            return false
        }
        return !visitHasTitle || abs(now.timeIntervalSince(visit.date)) <= titleUpdateInterval
    }

    /// Une adresse changée par la page compte si elle reste sur l'origine du dernier document chargé (l'History
    /// API ne peut pas en changer) : un échec de chargement vers un autre site ne devient pas une visite.
    static func isSameDocumentChange(from loaded: URL?, to url: URL) -> Bool {
        guard let loaded else {
            return false
        }
        return origin(of: loaded) == origin(of: url)
    }

    /// Visites gardées : un an (réglage par défaut de Safari) ; les plus anciennes sont effacées au lancement.
    static func retentionCutoff(now: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .year, value: -1, to: now) ?? now.addingTimeInterval(-365 * 86400)
    }

    private static func origin(of url: URL) -> String {
        let scheme = url.scheme?.lowercased() ?? ""
        let host = url.host()?.lowercased() ?? ""
        return "\(scheme)://\(host):\(url.port.map(String.init) ?? "")"
    }
}
