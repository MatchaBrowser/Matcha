import Foundation
import WebKit

/// Store of compiled blocklists (task 6.2): WebKit's in the app (`WKContentRuleListStore`), a fake one in the
/// `BlocklistLoader` tests.
@MainActor
protocol ContentRuleListStoring {
    associatedtype RuleList

    /// Compiled list `identifier`; nil if it is missing or can no longer be read (format of another WebKit version).
    func lookUp(_ identifier: String) async -> RuleList?
    /// Compiles `rules` (JSON in WebKit's format) under `identifier`, replacing a list with the same identifier.
    func compile(_ identifier: String, rules: String) async throws -> RuleList
    /// Identifiers of all the lists in the store.
    func identifiers() async -> [String]
    func remove(_ identifier: String) async throws
}

extension WKContentRuleListStore: ContentRuleListStoring {
    func lookUp(_ identifier: String) async -> WKContentRuleList? {
        // A missing list, or one compiled by another WebKit version, is an error: it must be recompiled.
        try? await contentRuleList(forIdentifier: identifier)
    }

    /// WebKit compiles on its own queue, off the main thread; the result comes back on the main thread.
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

/// Blocklist compilation errors.
nonisolated enum ContentRuleListError {
    /// True if WebKit refused a list because it has too many rules (`WKError.contentRuleListStoreCompileFailed`,
    /// message “Rule list compilation failed: Too many rules in JSON array.” under `NSHelpAnchorErrorKey`): it is
    /// then split.
    static func isTooManyRules(_ error: any Error) -> Bool {
        let error = error as NSError
        guard error.domain == WKError.errorDomain, error.code == WKError.Code.contentRuleListStoreCompileFailed.rawValue else {
            return false
        }
        let message = error.userInfo[NSHelpAnchorErrorKey] as? String ?? ""
        return message.localizedCaseInsensitiveContains("too many rules")
    }

    /// WebKit's message about a refused compilation (invalid rule…), for the log; otherwise the error's domain and
    /// code, never its description, which can hold a path (review SV6).
    static func message(of error: any Error) -> String {
        (error as NSError).userInfo[NSHelpAnchorErrorKey] as? String ?? error.logSummary
    }
}
