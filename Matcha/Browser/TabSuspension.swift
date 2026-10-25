import AppKit
import Observation

/// Snapshot laid over a page woken from sleep, while it reloads.
struct TabCover {
    let image: NSImage
    /// Width of the captured page, in points.
    let pageWidth: Double
}

/// Putting a tab to sleep to free its memory (task 5.6, `TabLifecycleService`). While asleep, the tab no longer has a
/// web view but keeps its address, title, icon and navigation state: the sidebar displays it as before, and it is
/// recreated when it is shown. Its snapshot, taken before sleep, then covers the recreated page during its first load,
/// for at most `coverDuration`; during this reload, an empty title or a missing address in the new web view do not
/// replace those of the tab.
@MainActor
@Observable
final class TabSuspension {
    /// Maximum duration of the snapshot over the recreated page: beyond it, the page shows itself even while loading.
    static let coverDuration = Duration.seconds(2)
    /// End of the reload with no answer from the page: the title and address follow the web view again.
    static let restoreTimeout = Duration.seconds(10)

    /// Followed page: read again at the end of the reload.
    @ObservationIgnored weak var page: BrowserTab?
    /// True while asleep.
    private(set) var isSuspended = false
    /// Snapshot shown over the recreated page, as long as it is not loaded.
    private(set) var cover: TabCover?
    /// Snapshot kept while asleep.
    @ObservationIgnored private(set) var snapshot: TabSnapshot?
    /// Moment the tab was put to sleep (the oldest snapshots go first).
    @ObservationIgnored private(set) var suspendedAt: Date?
    /// True from the recreation of the view until the end of its first load.
    @ObservationIgnored private(set) var isRestoring = false
    /// Address of the captured page that covers the recreated page.
    @ObservationIgnored private var coverURL: URL?
    @ObservationIgnored private var restoreTask: Task<Void, Never>?

    /// The web view has just been released.
    func didSuspend(snapshot: TabSnapshot?, at date: Date) {
        reset()
        isSuspended = true
        self.snapshot = snapshot
        suspendedAt = date
    }

    /// The web view is recreated to display `url`: the snapshot covers it if it shows that address.
    func didResume(url: URL?) {
        guard isSuspended else {
            return
        }
        isSuspended = false
        isRestoring = true
        if let snapshot, snapshot.url == url, let image = NSImage(data: snapshot.data) {
            cover = TabCover(image: image, pageWidth: snapshot.pageWidth)
            coverURL = url
        }
        snapshot = nil
        suspendedAt = nil
        restoreTask = Task { [weak self] in
            try? await Task.sleep(for: Self.coverDuration)
            guard !Task.isCancelled else {
                return
            }
            self?.dropCover()
            try? await Task.sleep(for: Self.restoreTimeout - Self.coverDuration)
            guard !Task.isCancelled else {
                return
            }
            self?.endRestoring()
        }
    }

    /// The address of the recreated page changed: a snapshot of another page no longer covers it.
    func pageURLDidChange(to url: URL?) {
        if let url, url != coverURL {
            dropCover()
        }
    }

    /// First load finished or failed, other navigation requested: the snapshot goes away, the tab follows the web view.
    func endRestoring() {
        guard isRestoring else {
            return
        }
        restoreTask?.cancel()
        restoreTask = nil
        isRestoring = false
        dropCover()
        page?.syncWithWebView()
    }

    /// The service keeps a limited number of snapshots: this one goes away, the sleep continues.
    func discardSnapshot() {
        snapshot = nil
    }

    /// Tab unloaded, brought back to another address or closed: no more sleep or snapshot. The observed values are
    /// only written if they change: the sidebar is not redrawn for nothing.
    func reset() {
        restoreTask?.cancel()
        restoreTask = nil
        if isSuspended {
            isSuspended = false
        }
        dropCover()
        isRestoring = false
        snapshot = nil
        suspendedAt = nil
    }

    /// Removes the snapshot from the page; the observed value is only written if it changes (`TabCover` isn't
    /// `Equatable`: Observation would notify for nil over nil).
    private func dropCover() {
        if cover != nil {
            cover = nil
        }
        coverURL = nil
    }
}
