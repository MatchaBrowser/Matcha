import Foundation
import WebKit

/// Failure while preparing an extension (task 6.4), shown to the user in their language.
nonisolated enum ExtensionInstallError: Error, Equatable, LocalizedError {
    /// Neither `.crx`, nor `.xpi`, nor `.zip`, nor a folder.
    case unknownFormat
    /// No `manifest.json` at the root (nor in a single subfolder).
    case noManifest
    /// Damaged, encrypted or too large archive, or in an unsupported format.
    case unreadable
    /// Manifest rejected by WebKit (unsupported manifest version, required field missing…).
    case invalidManifest(String)

    /// Error reported while reading the package, the archive, or by WebKit.
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
