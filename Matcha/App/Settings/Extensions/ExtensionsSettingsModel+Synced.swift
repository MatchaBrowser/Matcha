import AppKit
import Foundation

/// Réglages > Extensions, extensions proposées par vos autres Mac (tâche 7.4, `SYNC.md` § 2.5) : jamais installées sans
/// passer par l'écran des permissions.
extension ExtensionsSettingsModel {
    /// Peut-on ajouter l'extension proposée maintenant ?
    enum OfferAvailability: Equatable {
        case ready
        /// Extension Safari dont l'app n'est pas sur ce Mac.
        case appMissing
        /// Paquet absent : trop gros, ou synchro arrêtée.
        case packageUnavailable
    }

    /// Extensions des autres Mac en attente, par nom.
    var offers: [SyncExtensionFields] {
        syncAdapter.synced.sortedOffers
    }

    /// Déjà installée ici : une mise à jour qui demande une permission ou un site de plus.
    func isUpdate(_ offer: SyncExtensionFields) -> Bool {
        _ = revision
        return manager.installedIdentifiers.contains(offer.identifier)
    }

    func availability(of offer: SyncExtensionFields) -> OfferAvailability {
        switch offer.source.kind {
        case .appExtension:
            appExtensions.contains { $0.bundleIdentifier == offer.source.bundleIdentifier } ? .ready : .appMissing
        case .package:
            syncAdapter.transport?.supportsBlobs == true && SyncedPackage(source: offer.source, version: offer.version) != nil
                ? .ready : .packageUnavailable
        }
    }

    /// Prépare l'extension proposée pour l'écran des permissions.
    func addOffer(_ offer: SyncExtensionFields) {
        installingOffer = offer
        Task { [syncAdapter] in
            await prepare { _ in try await syncAdapter.prepareOffer(offer) }
        }
    }

    /// N'est plus proposée sur ce Mac.
    func ignoreOffer(_ offer: SyncExtensionFields) {
        syncAdapter.ignore(offer.identifier)
    }

    /// Page de l'app de l'extension dans l'App Store, sinon la page des extensions Safari.
    func openAppStore(for offer: SyncExtensionFields) {
        Task {
            if let url = await appStoreURL(of: offer), NSWorkspace.shared.open(url) {
                return
            }
            openAppStore()
        }
    }

    private func appStoreURL(of offer: SyncExtensionFields) async -> URL? {
        guard let bundleIdentifier = offer.source.appBundleIdentifier else {
            return nil
        }
        return await ExtensionSyncAdapter.appStoreURL(forBundleIdentifier: bundleIdentifier)
    }
}
