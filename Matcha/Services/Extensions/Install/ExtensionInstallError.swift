import Foundation
import WebKit

/// Échec de la préparation d'une extension (tâche 6.4), montré à l'utilisateur dans sa langue.
nonisolated enum ExtensionInstallError: Error, Equatable, LocalizedError {
    /// Ni `.crx`, ni `.xpi`, ni `.zip`, ni dossier.
    case unknownFormat
    /// Pas de `manifest.json` à la racine (ni dans un unique sous-dossier).
    case noManifest
    /// Archive abîmée, chiffrée, trop grosse ou d'un format non pris en charge.
    case unreadable
    /// Manifeste refusé par WebKit (version de manifeste non prise en charge, champ obligatoire absent…).
    case invalidManifest(String)

    /// Erreur rapportée par la lecture du paquet, de l'archive ou de WebKit.
    init(_ error: any Error) {
        switch error {
        case let error as ExtensionInstallError:
            self = error
        case ExtensionPackage.Failure.unknownFormat:
            self = .unknownFormat
        case is ExtensionPackage.Failure, is ZipArchive.Failure:
            self = .unreadable
        case let error as NSError where error.domain == WKWebExtension.errorDomain:
            self = .invalidManifest(error.localizedDescription)
        default:
            self = .unreadable
        }
    }

    var errorDescription: String? {
        switch self {
        case .unknownFormat:
            String(localized: "This file is not an extension. Choose a .crx, .xpi or .zip file, or an unpacked folder.")
        case .noManifest:
            String(localized: "No manifest.json file was found in this extension.")
        case .unreadable:
            String(localized: "This extension can't be read. The file may be damaged or in an unsupported format.")
        case let .invalidManifest(message):
            String(localized: "This extension can't be installed: \(message)")
        }
    }
}
