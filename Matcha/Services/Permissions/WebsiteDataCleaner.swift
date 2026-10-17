import Foundation
import OSLog
import WebKit

/// Enregistrements de données de WebKit qui appartiennent à un site, sans la liste publique des suffixes.
nonisolated enum WebsiteDataMatcher {
    /// Vrai si l'enregistrement `recordName` (son `displayName` : en général le domaine enregistrable, « google.com »,
    /// ou un hôte entier, « localhost ») couvre `host` (« mail.google.com ») : même hôte, ou hôte sous ce domaine.
    /// Un autre site qui partage seulement un suffixe (« notgoogle.com ») n'est jamais visé.
    static func matches(recordName: String, host: String) -> Bool {
        let name = normalized(recordName)
        let host = normalized(host)
        guard !name.isEmpty, !host.isEmpty else {
            return false
        }
        return host == name || host.hasSuffix(".\(name)")
    }

    private static func normalized(_ value: String) -> String {
        var value = value.trimmingCharacters(in: .whitespaces).lowercased()
        if value.hasSuffix(".") {
            value.removeLast()
        }
        return value.hasPrefix("www.") ? String(value.dropFirst(4)) : value
    }
}

/// « Effacer les cookies et les données du site » (réglages du site, tâche 5.2) : cookies, stockage, caches et autres
/// données du site dans le magasin d'un profil, sans toucher aux autres sites.
@MainActor
enum WebsiteDataCleaner {
    /// Efface les données de `host` dans `store` ; renvoie le nombre d'enregistrements effacés.
    @discardableResult
    static func removeData(forHost host: String, in store: WKWebsiteDataStore) async -> Int {
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        let records = await store.dataRecords(ofTypes: types)
        let matching = records.filter { WebsiteDataMatcher.matches(recordName: $0.displayName, host: host) }
        guard !matching.isEmpty else {
            Logger.permissions.info("Aucune donnée à effacer pour \(host, privacy: .private)")
            return 0
        }
        await store.removeData(ofTypes: types, for: matching)
        Logger.permissions.info("Données effacées pour \(host, privacy: .private) (\(matching.count, privacy: .public) enregistrements)")
        return matching.count
    }
}
