import Foundation

extension ExtensionState {
    /// Decisions after installing a version that asks for `permissions` and `patterns` (audit E2): what it asks for is
    /// granted, except what the user refused or removed in Settings (review EX3); grants for what it no longer asks for
    /// (nor offers as optional) are dropped; expired decisions go. A new installation starts from no decision:
    /// everything it asks for is granted.
    mutating func applyRequests(
        permissions: Set<String>,
        patterns: Set<String>,
        optionalPermissions: Set<String> = [],
        optionalPatterns: Set<String> = [],
        at date: Date = .now,
    ) {
        self = removingExpired(at: date)
        grantedPermissions = grantedPermissions.filter { permissions.contains($0.key) || optionalPermissions.contains($0.key) }
        grantedMatchPatterns = grantedMatchPatterns.filter { patterns.contains($0.key) || optionalPatterns.contains($0.key) }
        for permission in permissions where deniedPermissions[permission] == nil {
            grantedPermissions[permission] = .distantFuture
        }
        for pattern in patterns where deniedMatchPatterns[pattern] == nil && !revokedMatchPatterns.contains(pattern) {
            grantedMatchPatterns[pattern] = .distantFuture
        }
    }
}
