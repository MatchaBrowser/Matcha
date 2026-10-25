import Foundation
import Observation
import WebKit

/// Stage of a download.
nonisolated enum DownloadState: Equatable, Sendable {
    case downloading
    case finished
    case failed
    case cancelled
}

/// Window a download starts from: each browsing window shows its own. Those of a private window leave the list
/// when it closes; those of mini windows go with the main window.
nonisolated enum DownloadScope: Hashable, Sendable {
    case regular
    case privateWindow(UUID)
}

/// A download as the list shows it: from this app session, or restored from the saved list (`SavedDownload`).
/// The WebKit object (`WKDownload`) and the tracking of its progress only live for the duration of the download.
@MainActor
@Observable
final class DownloadItem: Identifiable {
    /// Minimum interval between two progress updates: WebKit reports it for every packet received.
    static let progressInterval = Duration.milliseconds(100)

    let id: UUID
    let scope: DownloadScope
    /// Requested address (before redirection).
    let sourceURL: URL?
    /// Page the download starts from, for the quarantine attribute.
    let pageURL: URL?
    /// Displayed name: the file's once its location is chosen, otherwise the last component of the address.
    private(set) var fileName: String
    /// File written in Downloads; nil until its location is chosen.
    private(set) var destinationURL: URL?
    private(set) var state = DownloadState.downloading
    private(set) var completedBytes: Int64 = 0
    /// Size announced by the server; nil if it is unknown.
    private(set) var totalBytes: Int64?
    /// Reason for a failure, in the user's language.
    private(set) var failureReason: String?

    /// WebKit download, kept while it is in progress.
    @ObservationIgnored private(set) var download: WKDownload?
    @ObservationIgnored private var progressObservation: NSKeyValueObservation?
    @ObservationIgnored private var lastProgressUpdate: ContinuousClock.Instant?

    init(download: WKDownload?, scope: DownloadScope, sourceURL: URL?, pageURL: URL?) {
        id = UUID()
        self.download = download
        self.scope = scope
        self.sourceURL = sourceURL
        self.pageURL = pageURL
        fileName = DownloadFileName.make(suggested: nil, url: sourceURL, mimeType: nil)
    }

    /// Download restored from the saved list (regular windows); a download interrupted by quitting the app comes
    /// back as failed.
    init(saved: SavedDownload) {
        id = saved.id
        scope = .regular
        sourceURL = nil
        pageURL = nil
        fileName = saved.fileName
        destinationURL = saved.fileURL
        completedBytes = saved.byteCount
        failureReason = saved.failureReason
        switch saved.outcome {
        case .finished:
            state = .finished
            totalBytes = saved.byteCount
        case .failed:
            state = .failed
        case .cancelled:
            state = .cancelled
        case .interrupted:
            state = .failed
            failureReason = String(
                localized: "Matcha quit before the download finished.",
                comment: "Reason shown for a download that was still in progress when the app quit",
            )
        }
    }

    var isActive: Bool {
        state == .downloading
    }

    /// Finished file that cannot be found: deleted or moved since. Looked at when the download finishes and when the
    /// list is shown (`checkFile`), never at each drawing (review IU6).
    private(set) var isFileMissing = false

    /// Looks again whether the finished file is still there.
    func checkFile() {
        let isMissing = state == .finished && !(destinationURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false)
        if isMissing != isFileMissing {
            isFileMissing = isMissing
        }
    }

    /// What the list keeps of this download; still in progress (app quitting), it is kept as interrupted.
    var savedDownload: SavedDownload {
        let outcome: SavedDownload.Outcome = switch state {
        case .downloading: .interrupted
        case .finished: .finished
        case .failed: .failed
        case .cancelled: .cancelled
        }
        return SavedDownload(
            id: id,
            fileName: fileName,
            fileURL: destinationURL,
            outcome: outcome,
            byteCount: completedBytes,
            failureReason: failureReason,
        )
    }

    /// Received fraction, from 0 to 1; nil if the size is unknown.
    var fractionCompleted: Double? {
        DownloadProgressSummary.fraction(completed: completedBytes, total: totalBytes)
    }

    /// Location chosen: the displayed name becomes the file's.
    func setDestination(_ url: URL) {
        destinationURL = url
        fileName = url.lastPathComponent
    }

    /// Follows `progress` (the `WKDownload`'s) until the download ends.
    func observe(_ progress: Progress) {
        update(from: progress, force: true)
        progressObservation = progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Self.onMain {
                self?.update(from: progress, force: false)
            }
        }
    }

    /// Successful end: the size is that of the written file.
    func markFinished(size: Int64?) {
        stopObserving()
        let size = size ?? completedBytes
        completedBytes = size
        totalBytes = size
        state = .finished
        checkFile()
    }

    func markFailed(reason: String?) {
        stopObserving()
        failureReason = reason
        state = .failed
    }

    func markCancelled() {
        stopObserving()
        state = .cancelled
    }

    /// Copies the progress, at most every `progressInterval` (except at the start and the end).
    private func update(from progress: Progress, force: Bool) {
        guard isActive else {
            return
        }
        let now = ContinuousClock.now
        let total = progress.totalUnitCount
        let completed = progress.completedUnitCount
        if !force, total <= 0 || completed < total, let lastProgressUpdate, now - lastProgressUpdate < Self.progressInterval {
            return
        }
        lastProgressUpdate = now
        completedBytes = max(0, completed)
        totalBytes = total > 0 ? total : nil
    }

    private func stopObserving() {
        progressObservation = nil
        download = nil
    }

    /// WebKit reports progress on the main thread; to be safe, a call coming from elsewhere is sent back there.
    private nonisolated static func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }
}
