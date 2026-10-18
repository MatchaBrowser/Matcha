import Foundation
import Security

/// Extension Safari d'une app installée (tâche 6.4) : un `.appex` au point `com.apple.Safari.web-extension`, avec son
/// `manifest.json`. Matcha la charge sur place (`WKWebExtension(appExtensionBundle:)`) : les mises à jour de l'app
/// (App Store) la mettent à jour.
nonisolated struct SafariAppExtension: Equatable, Identifiable, Sendable {
    let appURL: URL
    let appName: String
    let extensionURL: URL
    let bundleIdentifier: String
    /// Nom de l'extension donné par son manifeste, sinon celui de l'app (le nom du `.appex` est souvent générique :
    /// « Safari Extension »).
    let displayName: String

    var id: String {
        bundleIdentifier
    }
}

/// Cherche les extensions Safari des apps de `/Applications` (et de ses sous-dossiers directs, comme Utilitaires) et de
/// `~/Applications` : aucune API publique ne les liste. Lecture des `Info.plist` seulement. Type pur.
nonisolated enum SafariExtensionFinder {
    static let extensionPoint = "com.apple.Safari.web-extension"

    /// Dossiers d'apps habituels.
    static var applicationFolders: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(filePath: "/Applications", directoryHint: .isDirectory),
            home.appending(path: "Applications", directoryHint: .isDirectory),
        ]
    }

    /// Extensions Safari trouvées dans `folders`, triées par nom, chacune une fois.
    static func find(in folders: [URL] = applicationFolders, fileManager: FileManager = .default) -> [SafariAppExtension] {
        var found: [String: SafariAppExtension] = [:]
        for app in folders.flatMap({ apps(in: $0, fileManager: fileManager) }) {
            for item in extensions(of: app, fileManager: fileManager) where found[item.bundleIdentifier] == nil {
                found[item.bundleIdentifier] = item
            }
        }
        return found.values.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    /// Extensions Safari d'une app.
    static func extensions(of app: URL, fileManager: FileManager = .default) -> [SafariAppExtension] {
        let plugIns = app.appending(path: "Contents/PlugIns", directoryHint: .isDirectory)
        let appexes = ((try? fileManager.contentsOfDirectory(at: plugIns, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "appex" }
        let appName = displayName(ofBundleAt: app) ?? app.deletingPathExtension().lastPathComponent
        return appexes.compactMap { appex in
            guard let info = infoDictionary(ofBundleAt: appex),
                  (info["NSExtension"] as? [String: Any])?["NSExtensionPointIdentifier"] as? String == extensionPoint,
                  let bundleIdentifier = info["CFBundleIdentifier"] as? String,
                  fileManager.fileExists(atPath: appex.appending(path: "Contents/Resources/manifest.json").path)
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

    /// Identifiant que Safari donne à l'extension du `.appex` `url` : « identifiant du bundle (équipe) », l'équipe lue
    /// dans sa signature (« me.proton.pass.catalyst.safari-extension (2SB5Z68H26) ») ; sans signature d'équipe,
    /// l'identifiant du bundle seul. Les sites de l'extension l'appellent par cet identifiant (`externally_connectable`).
    static func safariIdentifier(ofAppExtensionAt url: URL) -> String? {
        guard let bundleIdentifier = infoDictionary(ofBundleAt: url)?["CFBundleIdentifier"] as? String else {
            return nil
        }
        guard let team = teamIdentifier(ofBundleAt: url) else {
            return bundleIdentifier
        }
        return "\(bundleIdentifier) (\(team))"
    }

    /// Équipe de développement qui a signé le bundle `url`, lue par l'API publique de Security.
    static func teamIdentifier(ofBundleAt url: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
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

    /// Apps d'un dossier et de ses sous-dossiers directs.
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
