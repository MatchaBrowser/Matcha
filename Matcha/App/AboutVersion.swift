import Foundation

/// Version shown by Matcha > About Matcha: the one of the build. A published build (`scripts/package.sh`,
/// `scripts/release.sh`) gives its full version, suffix included (“1.0.0-beta.1”, which the bundle's version can't
/// hold), and its build number; a Debug build gives its commit (`scripts/build-commit.sh`) in place of the build
/// number, which stays at the project's value there.
nonisolated struct AboutVersion: Equatable {
    /// Info.plist key holding the published version, empty outside the publishing scripts.
    static let releaseVersionKey = "MatchaReleaseVersion"
    /// File of the bundle holding the commit of a Debug build, empty otherwise.
    static let commitResource = "BuildCommit"

    /// “Version 1.0.0-beta.1” in the panel.
    let applicationVersion: String
    /// In parentheses after it: build number or commit.
    let build: String

    init(info: [String: Any], commit: String?) {
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? ""
        let releaseVersion = info[Self.releaseVersionKey] as? String ?? ""
        applicationVersion = releaseVersion.isEmpty ? shortVersion : releaseVersion
        let commit = commit?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        build = commit.isEmpty ? info["CFBundleVersion"] as? String ?? "" : commit
    }

    static func current(_ bundle: Bundle = .main) -> Self {
        let commit = bundle.url(forResource: commitResource, withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        return Self(info: bundle.infoDictionary ?? [:], commit: commit)
    }
}
