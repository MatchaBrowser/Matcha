import AppKit
import OSLog

/// Website icons: read from the page, downloaded, kept in memory and on disk, per domain. Downloads carry no cookies
/// and stop at `maximumSize`; files are read and decoded off the main thread, bitmaps only (`FaviconDecoder`,
/// audit W8).
@MainActor
final class FaviconService {
    /// Maximum size of a downloaded icon.
    nonisolated static let maximumSize = 1_000_000

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

    /// Already known icon of the domain: in memory, otherwise read from disk.
    func loadCachedIcon(forHost host: String) async -> Favicon? {
        if let favicon = cachedIcon(forHost: host) {
            return favicon
        }
        guard let file = fileURL(forHost: host), let data = await Self.read(file), let decoded = await FaviconDecoder.decode(data) else {
            return nil
        }
        let favicon = Favicon(decoded: decoded)
        memory.setObject(favicon, forKey: host as NSString)
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
            guard let data = await download(url), let decoded = await FaviconDecoder.decode(data) else {
                continue
            }
            let favicon = Favicon(decoded: decoded)
            store(data, favicon: favicon, forHost: host)
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
        guard response.expectedContentLength <= maximumSize else {
            return nil
        }
        var data = Data()
        do {
            for try await byte in bytes {
                guard data.count < maximumSize else {
                    return nil
                }
                data.append(byte)
            }
        } catch {
            return nil
        }
        return data
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
            Logger.favicons.error("Icon not saved to disk: \(error.logSummary, privacy: .public)")
        }
    }

    /// Cached file, off the main thread; nil beyond `maximumSize`.
    @concurrent
    private static func read(_ file: URL) async -> Data? {
        guard let size = try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= maximumSize else {
            return nil
        }
        return try? Data(contentsOf: file)
    }

    private func fileURL(forHost host: String) -> URL? {
        let name = String(host.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" })
        return directory?.appendingPathComponent(name, isDirectory: false)
    }
}
