import Foundation
import OSLog
import WebKit

/// Délégué de chaque `WKDownload` : place du fichier, fin, échec. Le fichier terminé porte l'attribut de quarantaine.
extension DownloadManager: WKDownloadDelegate {
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void,
    ) {
        guard let item = item(for: download) else {
            completionHandler(nil)
            return
        }
        guard let destination = reserveDestination(for: item, suggestedFilename: suggestedFilename, response: response) else {
            Logger.downloads.error("Dossier Téléchargements introuvable : téléchargement abandonné")
            stopTracking(item)
            item.markFailed(reason: String(localized: "The Downloads folder is not available."))
            saveList()
            completionHandler(nil)
            return
        }
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let item = item(for: download) else {
            return
        }
        stopTracking(item)
        releaseReservation(of: item)
        guard let destination = item.destinationURL else {
            item.markFailed(reason: nil)
            saveList()
            return
        }
        // Avant que la liste ne propose d'ouvrir le fichier.
        ensureQuarantine(of: item, at: destination)
        let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
        item.markFinished(size: size.map(Int64.init))
        recordFinish(in: item.scope)
        saveList()
        Logger.downloads.info("Téléchargement terminé (\(Self.origin(of: item), privacy: .public))")
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData _: Data?) {
        guard let item = item(for: download) else {
            return
        }
        stopTracking(item)
        if (error as? URLError)?.code == .cancelled {
            item.markCancelled()
            Logger.downloads.info("Téléchargement interrompu (\(Self.origin(of: item), privacy: .public))")
        } else {
            item.markFailed(reason: error.localizedDescription)
            Logger.downloads.error(
                "Téléchargement en échec (\(Self.origin(of: item), privacy: .public)) : \(error.localizedDescription, privacy: .public)",
            )
        }
        discardPartialFile(of: item)
        saveList()
    }

    /// Le fichier doit porter l'attribut de quarantaine ; la sandbox le pose d'elle-même, Matcha le pose s'il manque.
    /// Sans adresse pour un téléchargement privé : macOS les garderait dans son journal des téléchargements.
    private func ensureQuarantine(of item: DownloadItem, at destination: URL) {
        let isPrivate = item.scope != .regular
        let outcome = DownloadQuarantine.ensure(on: destination, properties: DownloadQuarantine.properties(
            sourceURL: isPrivate ? nil : item.sourceURL,
            pageURL: isPrivate ? nil : item.pageURL,
            agentName: DownloadQuarantine.agentName,
            bundleIdentifier: Bundle.main.bundleIdentifier,
        ))
        switch outcome {
        case .alreadyQuarantined:
            Logger.downloads.debug("Attribut de quarantaine déjà posé")
        case .added:
            Logger.downloads.notice("Attribut de quarantaine absent : posé par Matcha")
        case .failed:
            Logger.downloads.fault("Fichier téléchargé sans attribut de quarantaine")
        }
    }
}
