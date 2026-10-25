import AppKit
import OSLog
import WebKit

/// Website icons: read from inside the page (`FaviconPageReader`, with its network context), otherwise downloaded
/// without cookies, kept in memory and on disk (`FaviconDiskCache`), per domain. Both stop at `maximumSize`; files are
/// read and decoded off the main thread, bitmaps only (`FaviconDecoder`, audit W8). A tab not loaded yet shows the icon
/// kept on disk. Erasing the history or a website's data erases the icons it no longer needs (review SV1).
@MainActor
final class FaviconService {
    /// Maximum size of a downloaded icon.
    nonisolated static let maximumSize = 1_000_000

    /// `Caches/Favicons/` in the app's container.
    nonisolated static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Favicons", isDirectory: true)
    }

    private let disk: FaviconDiskCache?
    private let memory = NSCache<NSString, Favicon>()
    private let session: URLSession
    /// Download in progress per domain, shared by the tabs of the same website.
    private var downloads: [String: Task<Favicon?, Never>] = [:]
    /// Reading of a domain's file in progress, shared by the tabs of the same website (review SV3).
    private var diskReads: [String: Task<Favicon?, Never>] = [:]
    /// Last write or erasure on disk: each one waits for the previous one.
    private var diskQueue: Task<Void, Never>?
    /// True once the disk cache has been trimmed (`FaviconDiskCache.maximumFiles`) during this launch.
    private var hasTrimmed = false
    /// Domains whose icon has been successfully refreshed since launch.
    private var refreshedHosts: Set<String> = []

    /// `directory`: folder of the disk cache, or nil for an in-memory cache only.
    init(directory: URL?) {
        disk = directory.map(FaviconDiskCache.init(directory:))
        session = URLSession(configuration: Self.makeConfiguration())
    }

    /// No cookies, credentials or cache: an icon request tells a website nothing about the profile.
    nonisolated static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        return configuration
    }

    /// Icon of the domain already in memory.
    func cachedIcon(forHost host: String) -> Favicon? {
        memory.object(forKey: host as NSString)
    }

    /// Already known icon of the domain: in memory, otherwise read from disk, once for all the tabs that ask.
    func loadCachedIcon(forHost host: String) async -> Favicon? {
        if let favicon = cachedIcon(forHost: host) {
            return favicon
        }
        guard let disk else {
            return nil
        }
        let reading = diskReads[host] ?? Task {
            guard let data = await disk.read(forHost: host, maximumSize: Self.maximumSize),
                  let decoded = await FaviconDecoder.decode(data)
            else {
                return nil
            }
            return Favicon(decoded: decoded)
        }
        diskReads[host] = reading
        let favicon = await reading.value
        diskReads[host] = nil
        if let favicon, cachedIcon(forHost: host) == nil {
            memory.setObject(favicon, forKey: host as NSString)
        }
        return favicon
    }

    /// New document in `tab`: the known icon of its domain, at once from memory, otherwise once read from disk.
    func showCachedIcon(on tab: BrowserTab, host: String?) {
        guard let host, !host.isEmpty else {
            tab.favicon = nil
            return
        }
        tab.favicon = cachedIcon(forHost: host)
        guard tab.favicon == nil else {
            return
        }
        Task {
            let favicon = await loadCachedIcon(forHost: host)
            if let favicon, tab.favicon == nil, tab.url?.host() == host {
                tab.favicon = favicon
            }
        }
    }

    /// True while the domain's icon is being looked up (tests: wait for the end of an unsuccessful lookup).
    func isRefreshingIcon(forHost host: String) -> Bool {
        downloads[host] != nil
    }

    /// After a page loads: shows the domain's known icon right away, then fetches the one the page declares, once per
    /// domain and per launch.
    func refreshIcon(of tab: BrowserTab) {
        guard let pageURL = tab.url, let host = pageURL.host(), !host.isEmpty else {
            return
        }
        if let cached = cachedIcon(forHost: host) {
            tab.favicon = cached
        }
        let download: Task<Favicon?, Never>
        if let running = downloads[host] {
            download = running
        } else {
            guard refreshedHosts.insert(host).inserted else {
                return
            }
            download = Task {
                var candidates: [FaviconCandidate] = []
                if let webView = tab.webView {
                    candidates = await FaviconCandidate.extract(from: webView)
                    let urls = FaviconSelector.urlsToTry(candidates: candidates, pageURL: pageURL)
                    if let favicon = await self.readIcon(urls, in: webView, forHost: host) {
                        return favicon
                    }
                }
                return await self.fetchIcon(forPage: pageURL, candidates: candidates)
            }
            downloads[host] = download
        }
        Task {
            let favicon = await download.value
            downloads[host] = nil
            guard let favicon else {
                // Failure (network, page without a readable icon): new attempt at the next load of the website.
                refreshedHosts.remove(host)
                return
            }
            if tab.url?.host() == host {
                tab.favicon = favicon
            }
        }
    }

    /// The best icon the page itself can load, cached.
    private func readIcon(_ urls: [URL], in webView: WKWebView, forHost host: String) async -> Favicon? {
        guard let data = await FaviconPageReader.read(urls, from: webView, maximumSize: Self.maximumSize),
              let decoded = await FaviconDecoder.decode(data)
        else {
            return nil
        }
        let favicon = Favicon(decoded: decoded)
        store(decoded, favicon: favicon, forHost: host)
        return favicon
    }

    /// Downloads the best available icon for `pageURL` and caches it.
    func fetchIcon(forPage pageURL: URL, candidates: [FaviconCandidate]) async -> Favicon? {
        guard let host = pageURL.host(), !host.isEmpty else {
            return nil
        }
        for url in FaviconSelector.urlsToTry(candidates: candidates, pageURL: pageURL) {
            guard let data = await download(url), let decoded = await FaviconDecoder.decode(data) else {
                continue
            }
            let favicon = Favicon(decoded: decoded)
            store(decoded, favicon: favicon, forHost: host)
            return favicon
        }
        Logger.favicons.debug("No icon for \(host, privacy: .private)")
        return nil
    }

    /// Content of `url`; nil beyond `maximumSize`, without waiting for the end of a larger response.
    func download(_ url: URL) async -> Data? {
        await Self.download(url, session: session)
    }

    /// Off the main thread: the response is read as it comes.
    @concurrent
    private static func download(_ url: URL, session: URLSession) async -> Data? {
        guard let (bytes, response) = try? await session.bytes(from: url) else {
            return nil
        }
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            return nil
        }
        return try? await BoundedRead.data(of: bytes, expectedLength: response.expectedContentLength, limit: Int(maximumSize))
    }

    /// In memory, then on disk, off the main thread: the decoded icon, never the downloaded bytes (review SV3).
    private func store(_ decoded: DecodedFavicon, favicon: Favicon, forHost host: String) {
        memory.setObject(favicon, forKey: host as NSString)
        guard let disk else {
            return
        }
        let image = decoded.image
        let trims = !hasTrimmed
        hasTrimmed = true
        enqueue {
            await disk.write(image, forHost: host)
            if trims {
                await disk.trim()
            }
        }
    }

    /// Website data cleared: its icon is erased, and fetched again at its next load.
    func removeIcon(forHost host: String) async {
        memory.removeObject(forKey: host as NSString)
        refreshedHosts.remove(host)
        if let disk {
            await enqueue { await disk.remove(hosts: [host]) }.value
        }
    }

    /// History erased: only the icons of `hosts` stay (websites still in the history or in a tab); the others are
    /// fetched again at their next load.
    func removeIcons(keeping hosts: Set<String>) async {
        memory.removeAllObjects()
        refreshedHosts.formIntersection(hosts)
        if let disk {
            await enqueue { await disk.removeAll(keeping: hosts) }.value
        }
    }

    /// Waits for the writes and erasures on disk (tests).
    func waitForDisk() async {
        await diskQueue?.value
    }

    @discardableResult
    private func enqueue(_ operation: @escaping @Sendable () async -> Void) -> Task<Void, Never> {
        let previous = diskQueue
        let task = Task {
            await previous?.value
            await operation()
        }
        diskQueue = task
        return task
    }
}
