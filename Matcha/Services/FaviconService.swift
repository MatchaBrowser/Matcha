import AppKit
import OSLog

/// Icônes des sites : lues dans la page, téléchargées, gardées en mémoire et sur disque, par domaine.
@MainActor
final class FaviconService {
    static let shared = FaviconService(directory: defaultDirectory)

    /// Taille maximale d'une icône téléchargée.
    static let maximumSize = 1_000_000

    /// `Caches/Favicons/` dans le conteneur de l'app.
    nonisolated static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Favicons", isDirectory: true)
    }

    private let directory: URL?
    private let memory = NSCache<NSString, Favicon>()
    private let session: URLSession
    /// Téléchargement en cours par domaine, partagé par les onglets du même site.
    private var downloads: [String: Task<Favicon?, Never>] = [:]
    /// Domaines dont l'icône a été rafraîchie avec succès depuis le lancement.
    private var refreshedHosts: Set<String> = []

    /// `directory` : dossier du cache disque, ou nil pour un cache en mémoire seulement.
    init(directory: URL?) {
        self.directory = directory
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        session = URLSession(configuration: configuration)
    }

    /// Icône déjà connue du domaine : en mémoire, sinon sur disque.
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

    /// Vrai pendant la recherche de l'icône du domaine (tests : attendre la fin d'une recherche infructueuse).
    func isRefreshingIcon(forHost host: String) -> Bool {
        downloads[host] != nil
    }

    /// Après le chargement d'une page : affiche tout de suite l'icône connue du domaine, puis va chercher
    /// celle que déclare la page, une fois par domaine et par lancement.
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
                // Échec (réseau, page sans icône lisible) : nouvel essai au prochain chargement du site.
                refreshedHosts.remove(host)
                return
            }
            if tab.url?.host() == host {
                tab.favicon = favicon
            }
        }
    }

    /// Télécharge la meilleure icône disponible pour `pageURL` et la met en cache.
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
            Logger.favicons.error("Icône non enregistrée sur disque : \(error.localizedDescription, privacy: .public)")
        }
    }

    private func fileURL(forHost host: String) -> URL? {
        let name = String(host.map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? $0 : "_" })
        return directory?.appendingPathComponent(name, isDirectory: false)
    }
}
