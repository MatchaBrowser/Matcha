import CoreServices
import Foundation

/// Attribut de quarantaine (`com.apple.quarantine`) des fichiers téléchargés : Gatekeeper demande confirmation à la
/// première ouverture d'une app, d'un script ou d'une image disque.
///
/// La sandbox le pose d'elle-même sur tout fichier que WebKit écrit pour Matcha (agent « Matcha », type
/// « sandboxed »). Matcha le vérifie à chaque téléchargement terminé et ne le pose que s'il manque, par l'API
/// publique (`URLResourceValues.quarantineProperties`). Il ne complète pas un attribut existant : une app sandboxée
/// ne peut pas inscrire l'adresse dans le journal des téléchargements de macOS, l'ajout ne ferait que perdre le type.
nonisolated enum DownloadQuarantine {
    /// Issue de `ensure` (journal et tests).
    enum Outcome: Equatable {
        /// Le fichier portait déjà l'attribut (posé par la sandbox).
        case alreadyQuarantined
        /// L'attribut manquait : Matcha l'a posé.
        case added
        /// L'attribut manque et n'a pas pu être posé.
        case failed
    }

    /// Nom de l'app, celui que la sandbox inscrit dans l'attribut.
    static var agentName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Matcha"
    }

    /// Propriétés d'un fichier téléchargé : l'app, le type « téléchargement web », l'adresse du fichier et celle de
    /// la page d'où il vient (http et https seulement : une adresse `data:` contient le fichier lui-même).
    static func properties(sourceURL: URL?, pageURL: URL?, agentName: String, bundleIdentifier: String?) -> [String: Any] {
        var properties: [String: Any] = [
            kLSQuarantineAgentNameKey as String: agentName,
            kLSQuarantineTypeKey as String: kLSQuarantineTypeWebDownload as String,
        ]
        properties[kLSQuarantineAgentBundleIdentifierKey as String] = bundleIdentifier
        properties[kLSQuarantineDataURLKey as String] = recordedURL(sourceURL)
        properties[kLSQuarantineOriginURLKey as String] = recordedURL(pageURL)
        return properties
    }

    /// Adresse retenue dans les propriétés : http et https seulement, sans identifiant ni mot de passe.
    static func recordedURL(_ url: URL?) -> URL? {
        guard let url, ["http", "https"].contains(url.scheme?.lowercased()),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }
        components.user = nil
        components.password = nil
        return components.url
    }

    /// Propriétés de quarantaine du fichier, nil s'il n'en a pas (ou s'il est illisible).
    static func currentProperties(of fileURL: URL) -> [String: Any]? {
        // URL neuve : les valeurs de ressource sont mises en cache par objet.
        try? URL(fileURLWithPath: fileURL.path).resourceValues(forKeys: [.quarantinePropertiesKey]).quarantineProperties
    }

    /// Vérifie que le fichier porte l'attribut, et le pose avec `properties` s'il manque.
    static func ensure(on fileURL: URL, properties: @autoclosure () -> [String: Any]) -> Outcome {
        guard currentProperties(of: fileURL) == nil else {
            return .alreadyQuarantined
        }
        var target = URL(fileURLWithPath: fileURL.path)
        var values = URLResourceValues()
        values.quarantineProperties = properties()
        guard (try? target.setResourceValues(values)) != nil, currentProperties(of: fileURL) != nil else {
            return .failed
        }
        return .added
    }
}
