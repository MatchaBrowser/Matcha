import Foundation
import WebKit

/// Magasin de listes de blocage compilées (tâche 6.2) : celui de WebKit dans l'app (`WKContentRuleListStore`), un faux
/// dans les tests de `BlocklistLoader`.
@MainActor
protocol ContentRuleListStoring {
    associatedtype RuleList

    /// Liste compilée `identifier` ; nil si elle manque ou ne se relit plus (format d'une autre version de WebKit).
    func lookUp(_ identifier: String) async -> RuleList?
    /// Compile `rules` (JSON au format de WebKit) sous `identifier`, en remplaçant une liste du même identifiant.
    func compile(_ identifier: String, rules: String) async throws -> RuleList
    /// Identifiants de toutes les listes du magasin.
    func identifiers() async -> [String]
    func remove(_ identifier: String) async throws
}

extension WKContentRuleListStore: ContentRuleListStoring {
    func lookUp(_ identifier: String) async -> WKContentRuleList? {
        // Une liste absente, ou compilée par une autre version de WebKit, est une erreur : il faut la recompiler.
        try? await contentRuleList(forIdentifier: identifier)
    }

    /// WebKit compile sur sa propre file, hors du fil principal ; le résultat revient sur le fil principal.
    func compile(_ identifier: String, rules: String) async throws -> WKContentRuleList {
        guard let list = try await compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: rules) else {
            throw WKError(.contentRuleListStoreCompileFailed)
        }
        return list
    }

    func identifiers() async -> [String] {
        await availableIdentifiers() ?? []
    }

    func remove(_ identifier: String) async throws {
        try await removeContentRuleList(forIdentifier: identifier)
    }
}

/// Erreurs de compilation des listes de blocage.
nonisolated enum ContentRuleListError {
    /// Vrai si WebKit a refusé une liste parce qu'elle a trop de règles (`WKError.contentRuleListStoreCompileFailed`,
    /// message « Rule list compilation failed: Too many rules in JSON array. » sous `NSHelpAnchorErrorKey`) : elle est
    /// alors découpée.
    static func isTooManyRules(_ error: any Error) -> Bool {
        let error = error as NSError
        guard error.domain == WKError.errorDomain, error.code == WKError.Code.contentRuleListStoreCompileFailed.rawValue else {
            return false
        }
        let message = error.userInfo[NSHelpAnchorErrorKey] as? String ?? ""
        return message.localizedCaseInsensitiveContains("too many rules")
    }

    /// Message de WebKit sur une compilation refusée (règle invalide…), pour le journal ; jamais d'adresse.
    static func message(of error: any Error) -> String {
        let error = error as NSError
        return error.userInfo[NSHelpAnchorErrorKey] as? String ?? error.localizedDescription
    }
}
