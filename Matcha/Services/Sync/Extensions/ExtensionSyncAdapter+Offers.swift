import Foundation
import WebKit

/// Extensions offered by your other Macs (`SYNC.md` § 2.5): prepared for the permissions screen, never installed
/// without the user's consent.
extension ExtensionSyncAdapter {
    enum OfferError: Error, Equatable {
        /// Safari extension whose app is not on this Mac.
        case appMissing
        /// Missing package: extension too big, or sync turned off.
        case packageUnavailable
    }

    /// Prepares the offered extension `fields`: the one from its app on this Mac, or its downloaded package.
    func prepareOffer(_ fields: SyncExtensionFields) async throws -> ExtensionInstallCandidate {
        switch fields.source.kind {
        case .appExtension:
            guard let appExtension = await findAppExtension(of: fields) else {
                throw OfferError.appMissing
            }
            return try await installer.prepare(appExtension)
        case .package:
            guard let transport, transport.supportsBlobs, let package = SyncedPackage(source: fields.source, version: fields.version) else {
                throw OfferError.packageUnavailable
            }
            let file = try await downloadPackage(package, using: transport)
            defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
            return try await installer.prepare(fileAt: file, preferredIdentifier: fields.identifier)
        }
    }

    /// Safari extension of the offer, if its app is on this Mac; looked for off the main thread (review EX7).
    func findAppExtension(of fields: SyncExtensionFields) async -> SafariAppExtension? {
        guard let bundleIdentifier = fields.source.bundleIdentifier else {
            return nil
        }
        return await SafariExtensionFinder.findInBackground().first { $0.bundleIdentifier == bundleIdentifier }
    }

    /// The offered extension was just installed: its package is the one received (nothing to send back), it is no
    /// longer offered, and its state here becomes the reference of its record: the permissions and the private windows
    /// of the other Macs are never overwritten by this first state (`SYNC.md` § 2.5, review SY1).
    func didInstallOffer(_ fields: SyncExtensionFields) {
        if let package = SyncedPackage(source: fields.source, version: fields.version) {
            synced.packages[fields.identifier] = package
        }
        synced.offers[fields.identifier] = nil
        synced.adopted.insert(fields.identifier)
    }

    /// Extensions installed from an offer since the last sync; forgotten once read.
    func takeAdopted() -> Set<String> {
        let adopted = synced.adopted
        synced.adopted = []
        return adopted
    }

    /// The app's page in the App Store, found through the public iTunes Search API; nil if it is unknown.
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
