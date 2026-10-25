import Foundation
import Security

/// Safari extension of an installed app (task 6.4): an `.appex` at the `com.apple.Safari.web-extension` extension
/// point, with its `manifest.json`. Matcha loads it in place (`WKWebExtension(appExtensionBundle:)`): the app's updates
/// (App Store) update it.
nonisolated struct SafariAppExtension: Equatable, Identifiable, Sendable {
    let appURL: URL
    let appName: String
    let extensionURL: URL
    let bundleIdentifier: String
    /// Name of the extension given by its manifest, otherwise that of the app (the name of the `.appex` is often
    /// generic: “Safari Extension”).
    let displayName: String

    var id: String {
        bundleIdentifier
    }
}

/// Looks for the Safari extensions of the apps in `/Applications` (and its direct subfolders, like Utilities): no
/// public API lists them. In the sandbox, `~/Applications` is the app's container, not the user's folder: it isn't
/// read (audit E7). Reads `Info.plist` files, and keeps only extensions whose code signature is valid. Pure type.
nonisolated enum SafariExtensionFinder {
    static let extensionPoint = "com.apple.Safari.web-extension"

    /// Where apps are installed.
    static var applicationFolders: [URL] {
        [URL(filePath: "/Applications", directoryHint: .isDirectory)]
    }

    /// `find` off the main thread: it reads `/Applications` and checks signatures.
    @concurrent
    static func findInBackground() async -> [SafariAppExtension] {
        find()
    }

    /// Safari extensions found in `folders`, sorted by name, each one once. `checksSignatures`: false for the tests'
    /// unsigned apps only.
    static func find(
        in folders: [URL] = applicationFolders,
        fileManager: FileManager = .default,
        checksSignatures: Bool = true,
    ) -> [SafariAppExtension] {
        var found: [String: SafariAppExtension] = [:]
        for app in folders.flatMap({ apps(in: $0, fileManager: fileManager) }) {
            let items = extensions(of: app, fileManager: fileManager, checksSignatures: checksSignatures)
            for item in items where found[item.bundleIdentifier] == nil {
                found[item.bundleIdentifier] = item
            }
        }
        return found.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Safari extensions of an app.
    static func extensions(of app: URL, fileManager: FileManager = .default, checksSignatures: Bool = true) -> [SafariAppExtension] {
        let plugIns = app.appending(path: "Contents/PlugIns", directoryHint: .isDirectory)
        let appexes = ((try? fileManager.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "appex" }
        let appName = displayName(ofBundleAt: app) ?? app.deletingPathExtension().lastPathComponent
        return appexes.compactMap { appex in
            guard let info = infoDictionary(ofBundleAt: appex),
                  (info["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String == extensionPoint,
                  let bundleIdentifier = info["CFBundleIdentifier"] as? String,
                  fileManager.fileExists(atPath: appex.appending(path: "Contents/Resources/manifest.json").path),
                  !checksSignatures || hasValidSignature(appex)
            else {
                return nil
            }
            let resources = appex.appending(path: "Contents/Resources", directoryHint: .isDirectory)
            let name = ExtensionManifestFile(folder: resources)?.name.flatMap { $0.isEmpty ? nil : $0 } ?? appName
            return SafariAppExtension(
                appURL: app,
                appName: appName,
                extensionURL: appex,
                bundleIdentifier: bundleIdentifier,
                displayName: name,
            )
        }
    }

    /// Identifier that Safari gives to the extension of the `.appex` `url`: “bundle identifier (team)”, the team read
    /// from its signature (“me.proton.pass.catalyst.safari-extension (2SB5Z68H26)”); without a team signature, the
    /// bundle identifier alone. The extension's websites call it by this identifier (`externally_connectable`).
    static func safariIdentifier(ofAppExtensionAt url: URL) -> String? {
        guard let bundleIdentifier = infoDictionary(ofBundleAt: url)?["CFBundleIdentifier"] as? String else {
            return nil
        }
        guard let team = teamIdentifier(ofBundleAt: url) else {
            return bundleIdentifier
        }
        return "\(bundleIdentifier) (\(team))"
    }

    /// `safariIdentifier`, off the main thread: checking a signature hashes all the bundle's resources (review EX7).
    @concurrent
    static func identity(ofAppExtensionAt url: URL) async -> String? {
        safariIdentifier(ofAppExtensionAt: url)
    }

    /// True if the code signature of bundle `url` is intact (audit E7): an altered extension isn't offered, and its
    /// team, read from that signature, can be trusted.
    static func hasValidSignature(_ url: URL) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            return false
        }
        return SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
    }

    /// Development team that signed bundle `url`, read through the public Security API; nil if its signature isn't
    /// valid.
    static func teamIdentifier(ofBundleAt url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecStaticCodeCheckValidity(code, [], nil) == errSecSuccess
        else {
            return nil
        }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
              let information = information as? [String: Any]
        else {
            return nil
        }
        return information[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Apps of a folder and of its direct subfolders.
    private static func apps(in folder: URL, fileManager: FileManager) -> [URL] {
        let contents = (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        return contents.flatMap { url -> [URL] in
            if url.pathExtension == "app" {
                return [url]
            }
            let nested = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
            return nested.filter { $0.pathExtension == "app" }
        }
    }

    private static func infoDictionary(ofBundleAt url: URL) -> [String: Any]? {
        let plist = url.appending(path: "Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist) else {
            return nil
        }
        return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any]
    }

    private static func displayName(ofBundleAt url: URL) -> String? {
        let info = infoDictionary(ofBundleAt: url)
        return (info?["CFBundleDisplayName"] as? String) ?? (info?["CFBundleName"] as? String)
    }
}
