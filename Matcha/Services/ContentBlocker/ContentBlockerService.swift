import Foundation
import Observation
import OSLog
import WebKit

/// Ad and tracker blocker (task 6.2), one for the whole app: all profiles, mini windows and private windows. At
/// launch, the shipped lists (`BlocklistBundle`) are looked up or compiled in WebKit's store (`BlocklistLoader`)
/// without blocking the interface: pages load without the blocker until then, then the lists are added to each
/// tracked page and to the following ones. Each page has its own content controller; before each navigation of its
/// main document, its lists are added to it, or removed if its website has an exception (`ContentBlockerScope`). An
/// `ignore-previous-rules` rule does not carry over from one list to another in WebKit: a separate exception list
/// would have no effect (`DECISIONS.md`). Global setting “Block ads and trackers” (on by default); changing it
/// applies to the next loads, without reloading the pages.
@MainActor
@Observable
final class ContentBlockerService {
    static let shared = ContentBlockerService(defaults: .standard)
    /// False while the blocker is set aside (`FEATURES.md`): it is not started and its settings are hidden
    /// (Privacy, site settings); its code and tests remain. An extension (uBlock Origin Lite) stands in for it in the
    /// meantime.
    static let isAvailable = false

    enum State: Equatable {
        /// Not started (host app of the unit tests, tests).
        case idle
        case loading
        case ready
    }

    /// A ready list, for the settings.
    struct InstalledList: Identifiable, Equatable {
        let entry: BlocklistEntry
        let record: CompiledBlocklist

        var id: String {
            entry.identifier
        }
    }

    private(set) var state = State.idle
    /// Ready lists, in manifest order.
    private(set) var installedLists: [InstalledList] = []
    /// “Block ads and trackers” setting.
    var isEnabled: Bool {
        didSet {
            guard isEnabled != oldValue else {
                return
            }
            defaults?.set(isEnabled, forKey: BrowserSettings.Key.blocksAdsAndTrackers)
            let state = isEnabled ? "on" : "off"
            Logger.contentBlocker.info("Blocker \(state, privacy: .public)")
            applyToPages(reloadingSite: nil)
        }
    }

    /// Websites where the blocker is turned off, saved.
    @ObservationIgnored let exceptions: ContentBlockerExceptions
    @ObservationIgnored private let defaults: UserDefaults?
    @ObservationIgnored private var ruleLists: [WKContentRuleList] = []
    @ObservationIgnored private var pages = ContentBlockerPages()
    /// Website of an address for exceptions (replaced in tests: their `obtest:` pages have no website).
    @ObservationIgnored var siteOfURL: (URL?) -> String? = ContentBlockerExceptions.site(for:)

    /// `defaults`: settings and remembered compiled lists; nil (tests): nothing is read or written.
    init(defaults: UserDefaults?) {
        self.defaults = defaults
        exceptions = ContentBlockerExceptions(defaults: defaults)
        isEnabled = BrowserSettings.blocksAdsAndTrackers(in: defaults)
    }

    /// True when at least one list is ready.
    var hasLists: Bool {
        !installedLists.isEmpty
    }

    /// Tracked pages that are still open (tests).
    var trackedPageCount: Int {
        pages.count
    }

    /// At app launch: prepares the shipped lists, in the background. No effect if it is already started.
    func start() {
        guard state == .idle else {
            return
        }
        state = .loading
        Task {
            await load(from: BlocklistBundle(bundle: .main), store: .default())
        }
    }

    /// Prepares the lists of `source` in `store`, then adds them to the tracked pages. Tests pass their own lists and a
    /// temporary store, never the app's.
    func load(from source: BlocklistBundle, store: WKContentRuleListStore) async {
        state = .loading
        let clock = ContinuousClock()
        let start = clock.now
        let entries = await manifestEntries(from: source)
        let loader = BlocklistLoader(store: store, readRules: { try await source.rules(of: $0) })
        let loaded = await loader.load(entries, previous: CompiledBlocklist.load(from: defaults))
        CompiledBlocklist.save(loaded.map(\.record), to: defaults)
        // Lists from a previous load are removed from the pages before adding the new ones.
        pages.apply(ruleLists) { _ in false }
        ruleLists = loaded.flatMap(\.ruleLists)
        installedLists = loaded.map { InstalledList(entry: $0.entry, record: $0.record) }
        state = .ready
        let compiled = loaded.count { $0.wasCompiled }
        let duration = (clock.now - start).formatted(.units(allowed: [.seconds, .milliseconds]))
        Logger.contentBlocker.info(
            "Lists ready: \(loaded.count, privacy: .public) (\(compiled, privacy: .public) compiled), in \(duration, privacy: .public)",
        )
        applyToPages(reloadingSite: nil)
    }

    /// The main document of `webView` is about to be `url` (navigation allowed, or document shown): the lists are
    /// added to it, or removed if its website has an exception for `scope`.
    func prepare(_ webView: WKWebView, for url: URL?, scope: ContentBlockerScope?) {
        let key = pages.track(webView, site: siteOfURL(url), scope: scope)
        pages.apply(ruleLists, only: key, blocks: blocks)
    }

    /// Turns the blocker off (`isExcepted`) or back on for `site`, saved; its open pages reload.
    func setException(_ isExcepted: Bool, forSite site: String) {
        guard let site = ContentBlockerExceptions.normalized(site), exceptions.set(isExcepted, forSite: site) else {
            return
        }
        Logger.contentBlocker.info("Blocker \(isExcepted ? "turned off" : "turned on again", privacy: .public) on a site")
        exceptionsDidChange(forSite: site)
    }

    /// The exception for `site` changed (saved, or in a private window): the pages of that website whose state
    /// changes reload.
    func exceptionsDidChange(forSite site: String) {
        applyToPages(reloadingSite: site)
    }

    /// Adds or removes the lists on all pages; reloads those of `site` that changed.
    private func applyToPages(reloadingSite site: String?) {
        let changed = pages.apply(ruleLists, blocks: blocks)
        guard let site else {
            return
        }
        for page in changed where page.site == site {
            page.webView?.reload()
        }
    }

    /// True if the lists must be on `page`: blocker on, lists ready, website without an exception.
    private func blocks(_ page: ContentBlockerPages.Page) -> Bool {
        guard isEnabled, !ruleLists.isEmpty else {
            return false
        }
        guard let site = page.site, let scope = page.scope else {
            return true
        }
        return !scope.isExcepted(site: site)
    }

    private func manifestEntries(from source: BlocklistBundle) async -> [BlocklistEntry] {
        do {
            let lists = try await source.manifest()?.lists ?? []
            if lists.isEmpty {
                Logger.contentBlocker.info("No blocklist shipped: blocker inactive")
            }
            return lists
        } catch {
            let reason = error.localizedDescription
            Logger.contentBlocker.error("Unreadable blocklist manifest, blocker inactive: \(reason, privacy: .public)")
            return []
        }
    }
}
