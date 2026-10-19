import AppKit
import Foundation

/// Settings > Extensions, extensions offered by your other Macs (task 7.4, `SYNC.md` § 2.5): never installed without
/// going through the permissions screen.
extension ExtensionsSettingsModel {
    /// Can the offered extension be added now?
    enum OfferAvailability: Equatable {
        case ready
        /// Safari extension whose app is not on this Mac.
        case appMissing
        /// Package missing: too large, or sync stopped.
        case packageUnavailable
    }

    /// Pending extensions from the other Macs, by name.
    var offers: [SyncExtensionFields] {
        syncAdapter.synced.sortedOffers
    }

    /// Already installed here: an update that asks for one more permission or site.
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

    /// Prepares the offered extension for the permissions screen.
    func addOffer(_ offer: SyncExtensionFields) {
        installingOffer = offer
        Task { [syncAdapter] in
            await prepare { _ in try await syncAdapter.prepareOffer(offer) }
        }
    }

    /// No longer offered on this Mac.
    func ignoreOffer(_ offer: SyncExtensionFields) {
        syncAdapter.ignore(offer.identifier)
    }

    /// App Store page of the extension's app, otherwise the Safari extensions page.
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
