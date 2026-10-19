import AppKit
import Foundation
import Observation
import OSLog
import WebKit

/// Downloads of the whole app (task 5.1): those of all windows, peeks and mini windows arrive here through
/// `NavigationCoordinator`. Each file is written to the Downloads folder (`DownloadLocation`), under a free name
/// chosen when WebKit asks for it. The list of regular windows is kept from one launch to the next
/// (`SavedDownloadList`) until “Clear”; that of a private window, never. Nothing opens by itself, neither the list
/// nor the file.
@MainActor
@Observable
final class DownloadManager: NSObject {
    static let shared = DownloadManager()

    /// Downloads of this app session and those restored from the saved list, from newest to oldest.
    private(set) var items: [DownloadItem] = []
    /// Downloads finished since launch, per window: the sidebar button bounces for each one.
    private(set) var finishedCounts: [DownloadScope: Int] = [:]
    /// Folder where files are written; nil if it cannot be found.
    @ObservationIgnored let directory: @MainActor () -> URL?
    /// Downloads in progress, by WebKit object.
    @ObservationIgnored private var active: [ObjectIdentifier: DownloadItem] = [:]
    /// Names chosen for downloads whose file does not exist yet, or is not deleted yet (compared case-insensitively,
    /// like the disk).
    @ObservationIgnored private var reservedNames: Set<String> = []
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?
    /// Settings where the list is kept; nil (tests, test store): nothing is read or written.
    @ObservationIgnored private var defaults: UserDefaults?

    /// `directory`: read again for each download; replaced in tests by a temporary folder.
    init(directory: @escaping @MainActor () -> URL? = { DownloadLocation.directory() }) {
        self.directory = directory
        super.init()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.removePartialFiles()
                self?.saveList(includingActive: true)
            }
        }
    }

    /// Restores the list saved at the previous launch, then saves it at each download end and at each “Clear”.
    /// Once, at launch.
    func restoreList(from defaults: UserDefaults) {
        self.defaults = defaults
        let saved = SavedDownloadList.load(from: defaults)
        items.append(contentsOf: saved.map(DownloadItem.init(saved:)))
        Logger.downloads.info("Liste des téléchargements reprise : \(saved.count, privacy: .public)")
    }

    /// Saves the downloads of regular windows that are no longer in progress; when the app quits, also those in
    /// progress, as interrupted.
    func saveList(includingActive: Bool = false) {
        guard let defaults else {
            return
        }
        let saved = items.filter { $0.scope == .regular && (includingActive || !$0.isActive) }.map(\.savedDownload)
        SavedDownloadList.save(saved, to: defaults)
    }

    /// Downloads that a window shows, from newest to oldest.
    func items(in scope: DownloadScope) -> [DownloadItem] {
        items.filter { $0.scope == scope }
    }

    /// Takes charge of a download that WebKit just created: it goes to the top of the list.
    /// `pageURL`: page it starts from, for the quarantine attribute.
    @discardableResult
    func track(_ download: WKDownload, scope: DownloadScope, pageURL: URL?) -> DownloadItem {
        let item = DownloadItem(download: download, scope: scope, sourceURL: download.originalRequest?.url, pageURL: pageURL)
        download.delegate = self
        active[ObjectIdentifier(download)] = item
        item.observe(download.progress)
        insert(item)
        Logger.downloads.info("Téléchargement commencé (\(Self.origin(of: item), privacy: .private))")
        return item
    }

    /// Adds `item` to the top of the list (primitive of `track`, used as is by the tests).
    func insert(_ item: DownloadItem) {
        items.insert(item, at: 0)
    }

    /// “Cancel” button: the partial file is deleted once WebKit has stopped.
    func cancel(_ item: DownloadItem) {
        guard item.isActive else {
            return
        }
        let download = item.download
        stopTracking(item)
        item.markCancelled()
        saveList()
        Logger.downloads.info("Téléchargement annulé (\(Self.origin(of: item), privacy: .private))")
        guard let download else {
            discardPartialFile(of: item)
            return
        }
        download.cancel { [weak self] _ in
            self?.discardPartialFile(of: item)
        }
    }

    /// “Clear”: removes from a window's list what is no longer in progress; no file is deleted.
    func clear(in scope: DownloadScope) {
        items.removeAll { $0.scope == scope && !$0.isActive }
        saveList()
    }

    /// Private window closed: its downloads in progress are cancelled (partial files deleted), the finished ones
    /// stay in Downloads, and all of them leave the list.
    func forgetDownloads(in scope: DownloadScope) {
        for item in items where item.scope == scope && item.isActive {
            cancel(item)
        }
        items.removeAll { $0.scope == scope }
        finishedCounts[scope] = nil
    }

    func item(for download: WKDownload) -> DownloadItem? {
        active[ObjectIdentifier(download)]
    }

    func finishedCount(in scope: DownloadScope) -> Int {
        finishedCounts[scope, default: 0]
    }

    // MARK: WebKit delegate primitives (`+Delegate`)

    /// File location: a free name in the folder, reserved until the file exists; nil if the folder cannot be found
    /// (the download fails).
    func reserveDestination(for item: DownloadItem, suggestedFilename: String, response: URLResponse) -> URL? {
        guard let directory = directory() else {
            return nil
        }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = DownloadFileName.make(suggested: suggestedFilename, url: response.url ?? item.sourceURL, mimeType: response.mimeType)
        let unique = DownloadFileName.unique(name) { candidate in
            reservedNames.contains(Self.reservationKey(candidate)) || Self.itemExists(at: directory.appendingPathComponent(candidate))
        }
        reservedNames.insert(Self.reservationKey(unique))
        let destination = directory.appendingPathComponent(unique, isDirectory: false)
        item.setDestination(destination)
        return destination
    }

    /// The download is no longer tracked by WebKit: no more callbacks expected for it.
    func stopTracking(_ item: DownloadItem) {
        active = active.filter { $0.value !== item }
    }

    /// A download of `scope` has just finished.
    func recordFinish(in scope: DownloadScope) {
        finishedCounts[scope, default: 0] += 1
    }

    /// Releases the name reserved by `item`: its file now exists, or has been deleted.
    func releaseReservation(of item: DownloadItem) {
        if let name = item.destinationURL?.lastPathComponent {
            reservedNames.remove(Self.reservationKey(name))
        }
    }

    /// Deletes the partial file of a stopped download (never another one: its name was free and reserved), then
    /// releases its name.
    func discardPartialFile(of item: DownloadItem) {
        if let destination = item.destinationURL, Self.itemExists(at: destination) {
            do {
                try FileManager.default.removeItem(at: destination)
            } catch {
                Logger.downloads.error("Fichier partiel non effacé : \(error.logSummary, privacy: .public)")
            }
        }
        releaseReservation(of: item)
    }

    /// Host of the requested address, or its scheme (`data`, `blob`): never the full address in the log.
    static func origin(of item: DownloadItem) -> String {
        item.sourceURL?.host() ?? item.sourceURL?.scheme ?? "?"
    }

    /// App quitting: WebKit stops with it, the partial files have no future.
    private func removePartialFiles() {
        for item in items where item.isActive {
            discardPartialFile(of: item)
        }
    }

    /// True if something occupies this path, broken symbolic link included (`fileExists` would follow it).
    private static func itemExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private static func reservationKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }
}
