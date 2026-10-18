import Foundation

/// Identifiant stable d'une extension installée (tâche 6.4), valide pour `ExtensionInstallDirectory` : il fixe son
/// adresse (`webkit-extension://<identifiant>/`) et son stockage. Réinstaller la même extension (nouvelle version) donne
/// le même identifiant : elle remplace l'ancienne et garde ses données. Type pur.
nonisolated enum ExtensionIdentifier {
    /// Extension d'un fichier : son nom dans la langue par défaut du manifeste (« Dark Reader » → `dark-reader`), sinon
    /// son identifiant Firefox ; nil si ni l'un ni l'autre ne donne de lettre ou de chiffre ASCII.
    static func forPackage(_ file: ExtensionManifestFile) -> String? {
        file.name.flatMap(slug) ?? file.geckoIdentifier.flatMap(slug)
    }

    /// Extension Safari d'une app : préfixe `safari-` et l'identifiant de son bundle.
    static func forAppExtension(bundleIdentifier: String) -> String? {
        slug("safari-\(bundleIdentifier)")
    }

    /// Nom du manifeste, ou son texte traduit (`__MSG_cle__`, clé sans tenir compte de la casse) pris dans `messages`
    /// (`_locales/<default_locale>/messages.json`).
    static func name(in manifest: [String: Any], messages: [String: Any]?) -> String? {
        guard let raw = manifest["name"] as? String else {
            return nil
        }
        guard raw.hasPrefix("__MSG_"), raw.hasSuffix("__"), raw.count > 8 else {
            return raw
        }
        let key = raw.dropFirst(6).dropLast(2).lowercased()
        let entry = messages?.first { $0.key.lowercased() == key }?.value as? [String: Any]
        return entry?["message"] as? String
    }

    /// Minuscules ASCII, chiffres et tirets (accents retirés, le reste devient un tiret), 63 caractères au plus ; nil
    /// s'il ne reste rien.
    static func slug(_ text: String) -> String? {
        let folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        var result = ""
        for scalar in folded.lowercased().unicodeScalars {
            if ("a" ... "z").contains(scalar) || ("0" ... "9").contains(scalar) {
                result.unicodeScalars.append(scalar)
            } else if !result.isEmpty, result.last != "-" {
                result.append("-")
            }
        }
        var trimmed = String(result.prefix(ExtensionInstallDirectory.maximumIdentifierLength))
        while trimmed.last == "-" {
            trimmed.removeLast()
        }
        return ExtensionInstallDirectory.isValidIdentifier(trimmed) ? trimmed : nil
    }
}
