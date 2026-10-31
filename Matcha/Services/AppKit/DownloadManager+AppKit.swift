import Foundation
import OSLog

extension DownloadManager {
    /// The file must carry the quarantine attribute; the sandbox sets it on its own, Matcha sets it if it is missing.
    /// No address for a private download: macOS would keep them in its downloads log.
    func ensureQuarantine(of item: DownloadItem, at destination: URL) {
        let isPrivate = item.scope != .regular
        let outcome = DownloadQuarantine.ensure(on: destination, properties: DownloadQuarantine.properties(
            sourceURL: isPrivate ? nil : item.sourceURL,
            pageURL: isPrivate ? nil : item.pageURL,
            agentName: DownloadQuarantine.agentName,
            bundleIdentifier: Bundle.main.bundleIdentifier,
        ))
        switch outcome {
        case .alreadyQuarantined:
            Logger.downloads.debug("Quarantine attribute already set")
        case .added:
            Logger.downloads.notice("Quarantine attribute missing: set by Matcha")
        case .failed:
            Logger.downloads.fault("Downloaded file without a quarantine attribute")
        }
    }
}
