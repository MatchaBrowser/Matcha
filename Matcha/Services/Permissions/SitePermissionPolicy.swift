import Foundation

/// Rules of permission requests (task 5.2), without WebKit or interface.
nonisolated enum SitePermissionPolicy {
    enum Outcome: Equatable, Sendable {
        /// Remembered decisions: granted without asking anything.
        case grant
        /// A remembered decision denies: denied without asking anything.
        case deny
        /// The banner asks for these permissions, those without a remembered decision.
        case ask(Set<SitePermissionKind>)
    }

    /// A requested permission that is denied wins (WebKit grants or denies the whole request); all allowed: granted;
    /// otherwise, we ask for those that have no decision. An empty request is denied.
    static func evaluate(
        _ requested: Set<SitePermissionKind>,
        stored: [SitePermissionKind: SitePermissionDecision],
    ) -> Outcome {
        guard !requested.isEmpty, !requested.contains(where: { stored[$0] == .deny }) else {
            return .deny
        }
        let undecided = requested.filter { stored[$0] == nil }
        return undecided.isEmpty ? .grant : .ask(undecided)
    }

    /// Answer passed to WebKit.
    static func grants(_ answer: SitePermissionAnswer) -> Bool {
        answer != .deny
    }

    /// Decisions to remember for the `asked` permissions: none for “Allow Once”.
    static func decisionsToStore(
        for answer: SitePermissionAnswer,
        asked: Set<SitePermissionKind>,
    ) -> [SitePermissionKind: SitePermissionDecision] {
        switch answer {
        case .allowOnce:
            [:]
        case .alwaysAllow:
            Dictionary(uniqueKeysWithValues: asked.map { ($0, .allow) })
        case .deny:
            Dictionary(uniqueKeysWithValues: asked.map { ($0, .deny) })
        }
    }
}
