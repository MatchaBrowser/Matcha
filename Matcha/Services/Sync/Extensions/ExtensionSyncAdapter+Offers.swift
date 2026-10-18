import Foundation
import WebKit

/// Extensions proposées par vos autres Mac (`SYNC.md` § 2.5) : préparées pour l'écran des permissions, jamais
/// installées sans l'accord de l'utilisateur.
extension ExtensionSyncAdapter {
    enum OfferError: Error, Equatable {
        /// Extension Safari dont l'app n'est pas sur ce Mac.
        case appMissing
        /// Paquet absent : extension trop grosse, ou synchro arrêtée.
        case packageUnavailable
    }

    /// Prépare l'extension proposée `fields` : celle de son app sur ce Mac, ou son paquet téléchargé.
    func prepareOffer(_ fields: SyncExtensionFields) async throws -> ExtensionInstallCandidate {
        switch fields.source.kind {
        case .appExtension:
            guard let appExtension = findAppExtension(of: fields) else {
                throw OfferError.appMissing
            }
            return try await installer.prepare(appExtension)
        case .package:
            guard let transport, transport.supportsBlobs, let package = SyncedPackage(source: fields.source, version: fields.version) else {
                throw OfferError.packageUnavailable
            }
            let file = try await downloadPackage(package, using: transport)
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            return try await installer.prepare(fileAt: file)
        }
    }

    /// Extension Safari de l'offre, si son app est sur ce Mac.
    func findAppExtension(of fields: SyncExtensionFields) -> SafariAppExtension? {
        guard let bundleIdentifier = fields.source.bundleIdentifier else {
            return nil
        }
        return SafariExtensionFinder.find().first { $0.bundleIdentifier == bundleIdentifier }
    }

    /// L'extension proposée vient d'être installée : son paquet est celui reçu (rien à renvoyer), elle n'est plus
    /// proposée.
    func didInstallOffer(_ fields: SyncExtensionFields) {
        if let package = SyncedPackage(source: fields.source, version: fields.version) {
            synced.packages[fields.identifier] = package
        }
        synced.offers[fields.identifier] = nil
    }

    /// Page de l'app dans l'App Store, trouvée par l'API publique de recherche d'iTunes ; nil si elle est inconnue.
    static func appStoreURL(forBundleIdentifier bundleIdentifier: String, session: URLSession = .shared) async -> URL? {
        var components = URLComponents(string: "https://itunes.apple.com/lookup")
        components?.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleIdentifier),
            URLQueryItem(name: "entity", value: "macSoftware"),
        ]
        guard let url = components?.url, let (data, _) = try? await session.data(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = object["results"] as? [[String: Any]],
              let page = (results.first?["trackViewUrl"] as? String).flatMap(URLComponents.init(string:))
        else {
            return nil
        }
        var store = page
        store.scheme = "macappstore"
        return store.url
    }
}
