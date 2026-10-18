import Foundation
import Observation
import OSLog

/// Sites où le bloqueur est désactivé (tâche 6.2), pour tous les profils : un choix sur le site (une page cassée par le
/// blocage), pas une donnée d'un profil. Un site est le domaine enregistrable de l'adresse (`SiteDomain` :
/// « mail.google.com » → « google.com ») : l'exception vaut pour lui et tous ses sous-domaines, sur les pages dont le
/// document principal est de ce site (cadres d'autres sites compris, comme `if-domain` dans une liste de WebKit).
/// Enregistrés dans les réglages de l'app (`contentBlockerExceptions`) ; sans `defaults` (tests), tout reste en
/// mémoire. Les fenêtres privées n'y écrivent jamais (`ContentBlockerScope`).
@MainActor
@Observable
final class ContentBlockerExceptions {
    /// Réglage de l'app : liste des sites.
    static let defaultsKey = "contentBlockerExceptions"

    private(set) var sites: Set<String>
    @ObservationIgnored private let defaults: UserDefaults?

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        let stored = defaults?.stringArray(forKey: Self.defaultsKey) ?? []
        sites = Set(stored.compactMap(Self.normalized))
        if sites.count != stored.count {
            Logger.contentBlocker.notice("Exceptions du bloqueur illisibles ou en double : ignorées")
        }
    }

    /// Sites dans l'ordre alphabétique (réglages).
    var sortedSites: [String] {
        sites.sorted()
    }

    func contains(_ site: String) -> Bool {
        sites.contains(site)
    }

    /// Ajoute (`isExcepted`) ou retire `site` ; faux si rien ne change.
    @discardableResult
    func set(_ isExcepted: Bool, forSite site: String) -> Bool {
        guard let site = Self.normalized(site), contains(site) != isExcepted else {
            return false
        }
        if isExcepted {
            sites.insert(site)
        } else {
            sites.remove(site)
        }
        save()
        return true
    }

    /// Site de `url` pour les exceptions ; nil hors du web (`file:`, `about:`, schéma d'une app).
    nonisolated static func site(for url: URL?) -> String? {
        url.flatMap(SiteDomain.site(of:))
    }

    /// Site relu ou reçu : minuscules, sans espaces ni point final ; nil s'il est vide ou contient une barre, un espace
    /// ou une adresse complète.
    nonisolated static func normalized(_ site: String) -> String? {
        var site = site.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if site.hasSuffix(".") {
            site.removeLast()
        }
        let forbidden = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "/?#@"))
        guard !site.isEmpty, site.rangeOfCharacter(from: forbidden) == nil, !site.hasPrefix(".") else {
            return nil
        }
        return site
    }

    private func save() {
        guard let defaults else {
            return
        }
        if sites.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(sortedSites, forKey: Self.defaultsKey)
        }
    }
}
