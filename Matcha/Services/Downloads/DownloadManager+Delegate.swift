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
            Logger.downloads.error("Downloads folder not found: download dropped")
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
        Logger.downloads.info("Download finished (\(Self.origin(of: item), privacy: .private))")
    }

    func download(_ download: WKDownload, didFailWithError error: any Error, resumeData _: Data?) {
        guard let item = item(for: download) else {
            return
        }
        stopTracking(item)
        if (error as? URLError)?.code == .cancelled {
            item.markCancelled()
            Logger.downloads.info("Download interrupted (\(Self.origin(of: item), privacy: .private))")
        } else {
            item.markFailed(reason: error.localizedDescription)
            Logger.downloads.error(
                "Download failed (\(Self.origin(of: item), privacy: .private)): \(error.logSummary, privacy: .public)",
            )
        }
        discardPartialFile(of: item)
        saveList()
    }
}
