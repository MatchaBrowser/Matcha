import Foundation
import Observation
import OSLog
import WebKit

/// Memory of a session's tabs (task 5.6): a tab hidden for longer than the configured delay is put to sleep (snapshot,
/// navigation state remembered, web view released); it stays in the sidebar and is recreated when it is displayed. One
/// check per minute, and at each system memory warning: the oldest half of the hidden tabs (simple warning), or all of
/// them (critical warning), without snapshots. Rules: `TabSuspensionPolicy`. Only sees the sidebar tabs of the Spaces:
/// never Peek, nor the pages of mini windows or those of sign-in windows.
@MainActor
@Observable
final class TabLifecycleService {
    /// Maximum number of snapshots kept (the most recent ones), a few megabytes in total.
    static let maximumSnapshots = 30

    /// Open windows of the session, observed: opening or closing one changes what is visible.
    private var displays: [DisplayReference] = []
    @ObservationIgnored weak var session: BrowserSession?
    /// Settings read again at each check; replaced in the tests.
    @ObservationIgnored var settings: @MainActor () -> TabSuspensionSettings = { .current() }
    @ObservationIgnored var now: @MainActor () -> Date = { .now }
    @ObservationIgnored var probes = TabLifecycleProbes.webKit
    /// False in the tests: the machine's real memory warnings do not interfere with them.
    @ObservationIgnored var listensToMemoryPressure = true
    @ObservationIgnored private var tracker = TabVisibilityTracker()
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var pressureMonitor: MemoryPressureMonitor?
    /// Check in progress; the following ones wait for it.
    @ObservationIgnored private var pass: Task<Void, Never>?
    @ObservationIgnored private var passNumber = 0

    private struct DisplayReference {
        weak var display: (any TabDisplay)?
    }

    /// A window of the session is displayed: its displayed tabs become visible. Starts tracking on the first call.
    func windowDidAppear(_ display: any TabDisplay) {
        displays = displays.filter { $0.display != nil && $0.display !== display } + [DisplayReference(display: display)]
        start()
    }

    /// The window closes: its tabs are hidden from now on.
    func windowDidDisappear(_ display: any TabDisplay) {
        displays = displays.filter { $0.display != nil && $0.display !== display }
    }

    /// Tracks what is displayed, checks every minute and listens to memory warnings. No effect on a second call.
    func start() {
        guard !isStarted else {
            return
        }
        isStarted = true
        observeVisibility()
        timer = Task { [weak self] in
            while !Task.isCancelled {
                guard let interval = self?.settings().checkInterval else {
                    return
                }
                try? await Task.sleep(for: interval, tolerance: interval / 10)
                self?.schedule(.inactivity)
            }
        }
        guard listensToMemoryPressure else {
            return
        }
        pressureMonitor = MemoryPressureMonitor { [weak self] level in
            Logger.tabLifecycle.notice("Memory pressure: \(level.rawValue, privacy: .public)")
            self?.schedule(level == .critical ? .memoryCritical : .memoryWarning)
        }
    }

    /// Starts a check after the one in progress; a regular check is skipped if another one is still running.
    func schedule(_ reason: TabSuspensionReason) {
        if reason == .inactivity, pass != nil {
            return
        }
        let previous = pass
        passNumber += 1
        let number = passNumber
        pass = Task { [weak self] in
            await previous?.value
            await self?.check(reason)
            if let self, passNumber == number {
                pass = nil
            }
        }
    }

    /// Puts to sleep the tabs that the rules designate and returns their number.
    @discardableResult
    func check(_ reason: TabSuspensionReason) async -> Int {
        guard let delay = settings().delay else {
            return 0
        }
        refreshVisibility()
        let date = now()
        let visible = visibleTabIDs()
        let tabs = openTabs().filter(\.isLoaded)
        let byID = Dictionary(tabs.map { ($0.id, $0) }) { first, _ in first }
        let candidates = tabs.map { candidate(for: $0, visible: visible, now: date) }
        var idle: [UUID] = []
        for id in TabSuspensionPolicy.pool(candidates, reason: reason, delay: delay.timeInterval, now: date) {
            guard let webView = byID[id]?.webView else {
                continue
            }
            if await !probes.isPlayingMedia(webView) {
                idle.append(id)
            }
        }
        let selected = TabSuspensionPolicy.limit(idle, reason: reason)
        // Snapshots of the most recently left tabs (the end of the list), the most likely to be reopened; none during a
        // warning: they would require memory.
        let captured = reason == .inactivity ? Set(selected.suffix(Self.maximumSnapshots)) : []
        var count = 0
        for id in selected {
            guard let tab = byID[id], canSuspend(tab) else {
                continue
            }
            var snapshot: TabSnapshot?
            if captured.contains(id), let webView = tab.webView {
                snapshot = await probes.snapshot(webView, tab.url)
                // The tab may have been displayed or closed during the snapshot.
                guard canSuspend(tab) else {
                    continue
                }
            }
            tab.suspend(snapshot: snapshot, at: now())
            count += 1
        }
        trimSnapshots(keeping: reason == .memoryCritical ? 0 : Self.maximumSnapshots)
        if count > 0 {
            Logger.tabLifecycle.info("\(count, privacy: .public) tab(s) put to sleep (\(reason.rawValue, privacy: .public))")
        }
        return count
    }

    /// Since when `tab` has been hidden; nil if it is displayed or unknown.
    func hiddenSince(_ tab: BrowserTab) -> Date? {
        tracker.hiddenSince(tab.id)
    }

    /// True if `tab` is displayed in an open window of the session (task 5.7: a page whose process terminates reloads
    /// right away).
    func isVisible(_ tab: BrowserTab) -> Bool {
        visibleTabIDs().contains(tab.id)
    }

    /// Reads what is displayed again and records the time of the changes.
    func refreshVisibility() {
        tracker.update(visible: visibleTabIDs(), present: Set(openTabs().map(\.id)), now: now())
    }

    // MARK: Tracking

    /// Reads what is displayed again at each change (windows, displayed Space, selection, splits, open tabs).
    private func observeVisibility() {
        withObservationTracking {
            _ = visibleTabIDs()
            _ = openTabs()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeVisibility()
            }
        }
        refreshVisibility()
    }

    /// Tabs displayed in the open windows: the selected tab and its whole split, in the displayed Space. The
    /// originating tab of a Peek is one of them (Peek closes when that tab is no longer displayed).
    private func visibleTabIDs() -> Set<UUID> {
        var ids = Set<UUID>()
        for reference in displays {
            guard let manager = reference.display?.displayedTabManager else {
                continue
            }
            ids.formUnion(manager.displayedTabIDs)
            if let source = manager.peek?.sourceTabID {
                ids.insert(source)
            }
        }
        return ids
    }

    /// Sidebar tabs of all the Spaces of the session; a favorite shared by several Spaces appears only once.
    private func openTabs() -> [BrowserTab] {
        var seen = Set<ObjectIdentifier>()
        return (session?.spaces ?? []).flatMap(\.tabManager.tabs).filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    // MARK: Rules

    private func candidate(for tab: BrowserTab, visible: Set<UUID>, now: Date) -> TabLifecycleCandidate {
        let webView = tab.webView
        return TabLifecycleCandidate(
            id: tab.id,
            hiddenSince: visible.contains(tab.id) ? nil : tracker.hiddenSince(tab.id) ?? now,
            isLoaded: webView != nil,
            hasPendingPermissionPrompt: tab.permissionPrompts.hasPending,
            isCapturingMedia: webView.map { $0.cameraCaptureState != .none || $0.microphoneCaptureState != .none } ?? false,
            isPlayingAudio: tab.isPlayingAudio,
            hasOpenPopupWindow: session?.popupWindows.hasOpenWindow(openedBy: tab) ?? false,
        )
    }

    /// Checked just before releasing the view: the tab is still open, hidden and without any activity that forbids it.
    private func canSuspend(_ tab: BrowserTab) -> Bool {
        guard openTabs().contains(where: { $0 === tab }) else {
            return false
        }
        return TabSuspensionPolicy.isEligible(candidate(for: tab, visible: visibleTabIDs(), now: now()))
    }

    /// Keeps the `count` most recent snapshots of the sleeping tabs.
    private func trimSnapshots(keeping count: Int) {
        let suspended = openTabs()
            .filter { $0.suspension.snapshot != nil }
            .sorted { ($0.suspension.suspendedAt ?? .distantPast) > ($1.suspension.suspendedAt ?? .distantPast) }
        for tab in suspended.dropFirst(count) {
            tab.suspension.discardSnapshot()
        }
    }
}
