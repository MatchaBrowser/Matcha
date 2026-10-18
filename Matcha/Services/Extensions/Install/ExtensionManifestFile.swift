import Foundation

/// `manifest.json` d'une extension décompressée, et les textes de sa langue par défaut
/// (`_locales/<default_locale>/messages.json`) pour les noms en `__MSG_cle__` (tâche 6.4). Type pur.
nonisolated struct ExtensionManifestFile {
    let manifest: [String: Any]
    let messages: [String: Any]?

    /// Lit le manifeste du dossier `folder` ; nil s'il manque ou n'est pas un objet JSON.
    init?(folder: URL) {
        let manifestURL = folder.appendingPathComponent(ExtensionInstallDirectory.manifestName)
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = (try? JSONSerialization.jsonObject(with: Data(Self.removingByteOrderMark(data)))) as? [String: Any]
        else {
            return nil
        }
        self.manifest = manifest
        if let locale = manifest["default_locale"] as? String, !locale.contains("/"), !locale.contains("..") {
            let messagesURL = folder.appendingPathComponent("_locales/\(locale)/messages.json")
            messages = (try? Data(contentsOf: messagesURL))
                .flatMap { try? JSONSerialization.jsonObject(with: Self.removingByteOrderMark($0)) } as? [String: Any]
        } else {
            messages = nil
        }
    }

    /// Nom de l'extension dans sa langue par défaut.
    var name: String? {
        ExtensionIdentifier.name(in: manifest, messages: messages)
    }

    /// Identifiant de l'extension de Firefox (`browser_specific_settings.gecko.id`), s'il est donné.
    var geckoIdentifier: String? {
        let settings = (manifest["browser_specific_settings"] ?? manifest["applications"]) as? [String: Any]
        return (settings?["gecko"] as? [String: Any])?["id"] as? String
    }

    /// Certains manifestes commencent par une marque d'ordre des octets, que `JSONSerialization` refuse.
    private static func removingByteOrderMark(_ data: Data) -> Data {
        data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data
    }
}
