import Foundation
import OSLog

/// What Matcha remembers about an installed extension (task 6.3): enabled or not, and the user's decisions about its
/// permissions, which WebKit does not keep from one launch to the next (`WKWebExtensionContext.grantedPermissions` and
/// following: “This value should be saved and restored as needed by the app”). Keys as text: name of the permission
/// (“tabs”) or address pattern (“*://*.example.com/*”); value: expiration date (`Date.distantFuture` without
/// expiration). Pure type.
nonisolated struct ExtensionState: Codable, Equatable, Sendable {
    var isEnabled = true
    var grantedPermissions: [String: Date] = [:]
    var grantedMatchPatterns: [String: Date] = [:]
    var deniedPermissions: [String: Date] = [:]
    var deniedMatchPatterns: [String: Date] = [:]
    /// Private windows: denied by default, as in Safari; only the user opens them to an extension (6.4).
    var hasAccessToPrivateData = false
    var hasRequestedOptionalAccessToAllHosts = false
    /// Safari extension of an app (task 6.4): path of its `.appex`, loaded in place; nil for an extension copied into
    /// the extensions folder.
    var appExtensionPath: String?
    /// Button next to the address (task 6.5): false if it is hidden; nil (default): shown.
    var showsButton: Bool?
    /// Publisher proven by the installed file's signature (Chrome identifier of its developer, audit E1); nil if it
    /// couldn't be proven: then only the offer of your other Macs updates this extension and keeps its data, never a
    /// file chosen here (`ExtensionInstaller+Placement`).
    var publisher: String?
    /// Installed version, shown next to the one of an update.
    var version: String?
    /// Signed identity of an app's Safari extension at installation (“bundle identifier (team)”, audit E7): a bundle
    /// found later at the same place with another identity isn't loaded.
    var appExtensionIdentity: String?
    /// Websites the user removed in Settings (review EX3): the extension may ask for them again, but an update never
    /// grants them back by itself. A new grant lifts the removal.
    var revokedMatchPatterns: Set<String> = []
    /// Host of the extension's address (`webkit-extension://<host>/`), drawn at random when an app's Safari extension is
    /// installed (review EX8): websites can't guess it to probe its resources. Nil: its identifier (an extension from a
    /// file, whose identifier is already random, or a Safari extension installed before, whose pages keep their data).
    var baseURLHost: String?

    init() {}

    /// A missing field takes its default value: a field added later doesn't make the saved states unreadable
    /// (audit R4).
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        grantedPermissions = try container.decodeIfPresent([String: Date].self, forKey: .grantedPermissions) ?? [:]
        grantedMatchPatterns = try container.decodeIfPresent([String: Date].self, forKey: .grantedMatchPatterns) ?? [:]
        deniedPermissions = try container.decodeIfPresent([String: Date].self, forKey: .deniedPermissions) ?? [:]
        deniedMatchPatterns = try container.decodeIfPresent([String: Date].self, forKey: .deniedMatchPatterns) ?? [:]
        hasAccessToPrivateData = try container.decodeIfPresent(Bool.self, forKey: .hasAccessToPrivateData) ?? false
        hasRequestedOptionalAccessToAllHosts = try container
            .decodeIfPresent(Bool.self, forKey: .hasRequestedOptionalAccessToAllHosts) ?? false
        appExtensionPath = try container.decodeIfPresent(String.self, forKey: .appExtensionPath)
        showsButton = try container.decodeIfPresent(Bool.self, forKey: .showsButton)
        publisher = try container.decodeIfPresent(String.self, forKey: .publisher)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        appExtensionIdentity = try container.decodeIfPresent(String.self, forKey: .appExtensionIdentity)
        revokedMatchPatterns = try container.decodeIfPresent(Set<String>.self, forKey: .revokedMatchPatterns) ?? []
        baseURLHost = try container.decodeIfPresent(String.self, forKey: .baseURLHost)
    }

    /// Without the decisions expired at `date`.
    func removingExpired(at date: Date) -> ExtensionState {
        var state = self
        state.grantedPermissions = grantedPermissions.filter { $0.value > date }
        state.grantedMatchPatterns = grantedMatchPatterns.filter { $0.value > date }
        state.deniedPermissions = deniedPermissions.filter { $0.value > date }
        state.deniedMatchPatterns = deniedMatchPatterns.filter { $0.value > date }
        return state
    }
}
