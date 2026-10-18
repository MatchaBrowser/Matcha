import Foundation
import Observation
import OSLog
import WebKit

/// Mémoire des onglets d'une session (tâche 5.6) : un onglet caché depuis plus longtemps que le délai réglé est mis en
/// veille (capture, état de navigation retenu, vue web libérée) ; il reste dans la barre latérale et se recrée quand on
/// l'affiche. Une vérification par minute, et à chaque alerte mémoire du système : la moitié la plus ancienne des onglets
/// cachés (alerte simple), ou tous (alerte critique), sans capture. Règles : `TabSuspensionPolicy`. Ne voit que les
/// onglets rangés des Spaces : jamais l'aperçu, les pages des mini-fenêtres ni celles des fenêtres de connexion.
@MainActor
@Observable
final class TabLifecycleService {
    /// Captures gardées au plus (les plus récentes), quelques mégaoctets en tout.
    static let maximumSnapshots = 30

    /// Fenêtres ouvertes de la session, observées : en ouvrir ou en fermer change ce qui est visible.
    private var displays: [DisplayReference] = []
    @ObservationIgnored weak var session: BrowserSession?
    /// Réglages relus à chaque vérification ; remplacés dans les tests.
    @ObservationIgnored var settings: @MainActor () -> TabSuspensionSettings = { .current() }
    @ObservationIgnored var now: @MainActor () -> Date = { .now }
    @ObservationIgnored var probes = TabLifecycleProbes.webKit
    /// Faux dans les tests : les vraies alertes mémoire de la machine ne s'y mêlent pas.
    @ObservationIgnored var listensToMemoryPressure = true
    @ObservationIgnored private var tracker = TabVisibilityTracker()
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var timer: Task<Void, Never>?
    @ObservationIgnored private var pressureMonitor: MemoryPressureMonitor?
    /// Vérification en cours ; les suivantes l'attendent.
    @ObservationIgnored private var pass: Task<Void, Never>?
    @ObservationIgnored private var passNumber = 0

    private struct DisplayReference {
        weak var display: (any TabDisplay)?
    }

    /// Une fenêtre de la session s'affiche : ses onglets affichés deviennent visibles. Lance le suivi au premier appel.
    func windowDidAppear(_ display: any TabDisplay) {
        displays = displays.filter { $0.display != nil && $0.display !== display } + [DisplayReference(display: display)]
        start()
    }

    /// La fenêtre se ferme : ses onglets sont cachés à partir de maintenant.
    func windowDidDisappear(_ display: any TabDisplay) {
        displays = displays.filter { $0.display != nil && $0.display !== display }
    }

    /// Suit ce qui est affiché, vérifie chaque minute et écoute les alertes mémoire. Sans effet au second appel.
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
            Logger.tabLifecycle.notice("Alerte mémoire : \(level.rawValue, privacy: .public)")
            self?.schedule(level == .critical ? .memoryCritical : .memoryWarning)
        }
    }

    /// Lance une vérification après celle en cours ; une vérification régulière est sautée si une autre tourne encore.
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

    /// Met en veille les onglets que les règles désignent et renvoie leur nombre.
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
        // Captures des onglets quittés le plus récemment (la fin de la liste), les plus susceptibles d'être rouverts ;
        // aucune pendant une alerte : elles demanderaient de la mémoire.
        let captured = reason == .inactivity ? Set(selected.suffix(Self.maximumSnapshots)) : []
        var count = 0
        for id in selected {
            guard let tab = byID[id], canSuspend(tab) else {
                continue
            }
            var snapshot: TabSnapshot?
            if captured.contains(id), let webView = tab.webView {
                snapshot = await probes.snapshot(webView, tab.url)
                // L'onglet a pu être affiché ou fermé pendant la capture.
                guard canSuspend(tab) else {
                    continue
                }
            }
            tab.suspend(snapshot: snapshot, at: now())
            count += 1
        }
        trimSnapshots(keeping: reason == .memoryCritical ? 0 : Self.maximumSnapshots)
        if count > 0 {
            Logger.tabLifecycle.info("\(count, privacy: .public) onglet(s) mis en veille (\(reason.rawValue, privacy: .public))")
        }
        return count
    }

    /// Depuis quand `tab` est caché ; nil s'il est affiché ou inconnu.
    func hiddenSince(_ tab: BrowserTab) -> Date? {
        tracker.hiddenSince(tab.id)
    }

    /// Vrai si `tab` est affiché dans une fenêtre ouverte de la session (tâche 5.7 : une page dont le processus s'arrête
    /// se recharge tout de suite).
    func isVisible(_ tab: BrowserTab) -> Bool {
        visibleTabIDs().contains(tab.id)
    }

    /// Relit ce qui est affiché et note l'heure des changements.
    func refreshVisibility() {
        tracker.update(visible: visibleTabIDs(), present: Set(openTabs().map(\.id)), now: now())
    }

    // MARK: Suivi

    /// Relit ce qui est affiché à chaque changement (fenêtres, Space affiché, sélection, splits, onglets ouverts).
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

    /// Onglets affichés dans les fenêtres ouvertes : l'onglet sélectionné et tout son split, dans le Space affiché.
    /// L'onglet d'origine d'un aperçu en fait partie (l'aperçu se ferme quand il n'est plus affiché).
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

    /// Onglets rangés de tous les Spaces de la session ; un favori commun à plusieurs Spaces n'y est qu'une fois.
    private func openTabs() -> [BrowserTab] {
        var seen = Set<ObjectIdentifier>()
        return (session?.spaces ?? []).flatMap(\.tabManager.tabs).filter { seen.insert(ObjectIdentifier($0)).inserted }
    }

    // MARK: Règles

    private func candidate(for tab: BrowserTab, visible: Set<UUID>, now: Date) -> TabLifecycleCandidate {
        let webView = tab.webView
        return TabLifecycleCandidate(
            id: tab.id,
            hiddenSince: visible.contains(tab.id) ? nil : tracker.hiddenSince(tab.id) ?? now,
            isLoaded: webView != nil,
            hasPendingPermissionPrompt: tab.permissionPrompts.current != nil,
            isCapturingMedia: webView.map { $0.cameraCaptureState != .none || $0.microphoneCaptureState != .none } ?? false,
            isPlayingAudio: tab.isPlayingAudio,
            hasOpenPopupWindow: session?.popupWindows.hasOpenWindow(openedBy: tab) ?? false,
        )
    }

    /// Vérifié juste avant de libérer la vue : l'onglet est toujours ouvert, caché et sans activité qui l'interdit.
    private func canSuspend(_ tab: BrowserTab) -> Bool {
        guard openTabs().contains(where: { $0 === tab }) else {
            return false
        }
        return TabSuspensionPolicy.isEligible(candidate(for: tab, visible: visibleTabIDs(), now: now()))
    }

    /// Garde les `count` captures les plus récentes des onglets en veille.
    private func trimSnapshots(keeping count: Int) {
        let suspended = openTabs()
            .filter { $0.suspension.snapshot != nil }
            .sorted { ($0.suspension.suspendedAt ?? .distantPast) > ($1.suspension.suspendedAt ?? .distantPast) }
        for tab in suspended.dropFirst(count) {
            tab.suspension.discardSnapshot()
        }
    }
}
