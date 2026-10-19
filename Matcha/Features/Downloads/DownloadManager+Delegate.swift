import Foundation
import OSLog
import WebKit

/// Delegate of each `WKDownload`: file location, end, failure. The finished file carries the quarantine attribute.
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
        // Before the list offers to open the file.
        ensureQuarantine(of: item, at: destination)
        let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
        item.markFinished(size: size.map(Int64.init))
        recordFinish(in: item.scope)
        saveList()
        Logger.downloads.info("Téléchargement terminé (\(Self.origin(of: item), privacy: .private))")
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData _: Data?) {
        guard let item = item(for: download) else {
            return
        }
        stopTracking(item)
        if (error as? URLError)?.code == .cancelled {
            item.markCancelled()
            Logger.downloads.info("Téléchargement interrompu (\(Self.origin(of: item), privacy: .private))")
        } else {
            item.markFailed(reason: error.localizedDescription)
            Logger.downloads.error(
                "Téléchargement en échec (\(Self.origin(of: item), privacy: .private)) : \(error.logSummary, privacy: .public)",
            )
        }
        discardPartialFile(of: item)
        saveList()
    }

    /// The file must carry the quarantine attribute; the sandbox sets it on its own, Matcha sets it if it is missing.
    /// No address for a private download: macOS would keep them in its downloads log.
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
