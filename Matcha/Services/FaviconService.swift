import AppKit
import OSLog

/// Website icons: read from the page, downloaded, kept in memory and on disk, per domain.
@MainActor
final class FaviconService {
    static let shared = FaviconService(directory: defaultDirectory)

    /// Maximum size of a downloaded icon.
    static let maximumSize = 1_000_000

    /// `Caches/Favicons/` in the app's container.
    nonisolated static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Favicons", isDirectory: true)
    }

    private let directory: URL?
    private let memory = NSCache<NSString, Favicon>()
    private let session: URLSession
    /// Download in progress per domain, shared by the tabs of the same website.
    private var downloads: [String: Task<Favicon?, Never>] = [:]
    /// Domains whose icon has been successfully refreshed since launch.
    private var refreshedHosts: Set<String> = []

    /// `directory`: folder of the disk cache, or nil for an in-memory cache only.
    init(directory: URL?) {
        self.directory = directory
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
    }

    /// Already known icon of the domain: in memory, otherwise on disk.
    func cachedIcon(forHost host: String) -> Favicon? {
        if let favicon = memory.object(forKey: host as NSString) {
            return favicon
        }
        guard let file = fileURL(forHost: host), let data = try? Data(contentsOf: file), let favicon = Favicon(data: data) else {
            return nil
        }
        memory.setObject(favicon, forKey: host as NSString)
        return favicon
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

    /// Downloads the best available icon for `pageURL` and caches it.
    func fetchIcon(forPage pageURL: URL, candidates: [FaviconCandidate]) async -> Favicon? {
        guard let host = pageURL.host(), !host.isEmpty else {
            return nil
        }
        for url in FaviconSelector.urlsToTry(candidates: candidates, pageURL: pageURL) {
            guard let data = await download(url), let favicon = Favicon(data: data) else {
                continue
            }
            store(data, favicon: favicon, forHost: host)
            return favicon
        }
        Logger.favicons.debug("Aucune icône pour \(host, privacy: .private)")
        return nil
    }

    private func download(_ url: URL) async -> Data? {
        guard let (data, response) = try? await session.data(from: url) else {
            return nil
        }
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            return nil
        }
        return data.count <= Self.maximumSize ? data : nil
    }

    private func store(_ data: Data, favicon: Favicon, forHost host: String) {
        memory.setObject(favicon, forKey: host as NSString)
        guard let directory, let file = fileURL(forHost: host) else {
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: file, options: .atomic)
        } catch {
            Logger.favicons.error("Icône non enregistrée sur disque : \(error.logSummary, privacy: .public)")
        }
    }

    private func fileURL(forHost host: String) -> URL? {
        let name = String(host.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" })
        return directory?.appendingPathComponent(name, isDirectory: false)
    }
}
