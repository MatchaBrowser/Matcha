import Foundation
import OSLog

/// Liste de blocage compilée dans le magasin de WebKit (tâche 6.2), retenue dans les réglages de l'app : au lancement
/// suivant, la même version est relue telle quelle (`WKContentRuleListStore.lookUpContentRuleList`) au lieu d'être
/// recompilée. Le nombre de règles et la date servent aux réglages.
nonisolated struct CompiledBlocklist: Codable, Equatable, Sendable {
    /// Réglage de l'app : les listes compilées, en JSON.
    static let defaultsKey = "contentBlockerCompiledLists"
    /// Début des identifiants de nos listes dans le magasin : les autres identifiants n'y sont jamais touchés.
    static let storePrefix = "matcha-blocklist."

    let identifier: String
    let version: String
    /// Listes du magasin : une seule, ou une par part si WebKit a refusé la liste entière (trop de règles).
    let storeIdentifiers: [String]
    let ruleCount: Int
    let compiledAt: Date

    /// Identifiant dans le magasin de la liste `entry` entière (« matcha-blocklist.easylist.2026.10.18 ») ou de ses
    /// parts (« ….part-1 », « ….part-2 »…) : la version en fait partie, une nouvelle version ne remplace donc jamais
    /// l'ancienne avant d'être prête.
    static func storeIdentifiers(for entry: BlocklistEntry, partCount: Int) -> [String] {
        let base = "\(storePrefix)\(entry.identifier).\(entry.version)"
        guard partCount > 1 else {
            return [base]
        }
        return (1 ... partCount).map { "\(base).part-\($0)" }
    }

    /// Vrai si `self` est la version compilée de `entry` (même identifiant, même version, parts nommées pour elle) :
    /// il reste à la relire dans le magasin.
    func matches(_ entry: BlocklistEntry) -> Bool {
        identifier == entry.identifier && version == entry.version && !storeIdentifiers.isEmpty
            && storeIdentifiers == Self.storeIdentifiers(for: entry, partCount: storeIdentifiers.count)
    }

    /// Nos identifiants du magasin qui ne servent plus (ancienne version, liste retirée de l'app, compilation
    /// interrompue), triés ; ceux d'un autre préfixe ne sont jamais rendus.
    static func staleIdentifiers(available: [String], keeping kept: Set<String>) -> [String] {
        available.filter { $0.hasPrefix(storePrefix) && !kept.contains($0) }.sorted()
    }

    /// Listes retenues dans `defaults` ; aucune sans réglages, ou si la valeur est illisible.
    static func load(from defaults: UserDefaults?) -> [CompiledBlocklist] {
        guard let data = defaults?.data(forKey: defaultsKey) else {
            return []
        }
        do {
            return try JSONDecoder().decode([CompiledBlocklist].self, from: data)
        } catch {
            Logger.contentBlocker.notice("Listes compilées retenues illisibles : elles seront recompilées")
            return []
        }
    }

    static func save(_ lists: [CompiledBlocklist], to defaults: UserDefaults?) {
        guard let defaults else {
            return
        }
        if lists.isEmpty {
            defaults.removeObject(forKey: defaultsKey)
        } else if let data = try? JSONEncoder().encode(lists) {
            defaults.set(data, forKey: defaultsKey)
        }
    }
}
