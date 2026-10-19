import Foundation

/// `manifest.json` of an unpacked extension, and the texts of its default language
/// (`_locales/<default_locale>/messages.json`) for `__MSG_cle__` names (task 6.4). Pure type.
nonisolated struct ExtensionManifestFile {
    let manifest: [String: Any]
    let messages: [String: Any]?

    /// Reads the manifest of folder `folder`; nil if it is missing or is not a JSON object.
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

    /// Name of the extension in its default language.
    var name: String? {
        ExtensionIdentifier.name(in: manifest, messages: messages)
    }

    /// Firefox identifier of the extension (`browser_specific_settings.gecko.id`), if given.
    var geckoIdentifier: String? {
        let settings = (manifest["browser_specific_settings"] ?? manifest["applications"]) as? [String: Any]
        return (settings?["gecko"] as? [String: Any])?["id"] as? String
    }

    /// Some manifests start with a byte order mark, which `JSONSerialization` rejects.
    private static func removingByteOrderMark(_ data: Data) -> Data {
        data.starts(with: [0xEF, 0xBB, 0xBF]) ? data.dropFirst(3) : data
    }
}
