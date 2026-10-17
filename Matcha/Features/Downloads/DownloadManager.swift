import AppKit
import Foundation
import Observation
import OSLog
import WebKit

/// Téléchargements de toute l'app (tâche 5.1) : ceux de toutes les fenêtres, aperçus et mini-fenêtres arrivent ici
/// par `NavigationCoordinator`. Chaque fichier est écrit dans le dossier Téléchargements (`DownloadLocation`), sous un
/// nom libre choisi au moment où WebKit le demande. La liste ne vit que le temps de la session de l'app : rien n'est
/// enregistré. Rien ne s'ouvre de soi-même, ni la liste ni le fichier.
@MainActor
@Observable
final class DownloadManager: NSObject {
    static let shared = DownloadManager()

    /// Téléchargements de cette session de l'app, du plus récent au plus ancien.
    private(set) var items: [DownloadItem] = []
    /// Téléchargements terminés depuis le lancement, par fenêtre : le bouton de la barre rebondit à chacun.
    private(set) var finishedCounts: [DownloadScope: Int] = [:]
    /// Dossier où écrire les fichiers ; nil s'il est introuvable.
    @ObservationIgnored let directory: @MainActor () -> URL?
    /// Téléchargements en cours, par objet WebKit.
    @ObservationIgnored private var active: [ObjectIdentifier: DownloadItem] = [:]
    /// Noms choisis pour des téléchargements dont le fichier n'existe pas encore, ou n'est pas encore effacé
    /// (comparés sans tenir compte de la casse, comme le disque).
    @ObservationIgnored private var reservedNames: Set<String> = []
    @ObservationIgnored private var terminationObserver: (any NSObjectProtocol)?

    /// `directory` : relu à chaque téléchargement ; remplacé dans les tests par un dossier temporaire.
    init(directory: @escaping @MainActor () -> URL? = { DownloadLocation.directory() }) {
        self.directory = directory
        super.init()
        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.removePartialFiles() }
        }
    }

    /// Téléchargements que montre une fenêtre, du plus récent au plus ancien.
    func items(in scope: DownloadScope) -> [DownloadItem] {
        items.filter { $0.scope == scope }
    }

    /// Prend en charge un téléchargement que WebKit vient de créer : il entre en tête de la liste.
    /// `pageURL` : page d'où il part, pour l'attribut de quarantaine.
    @discardableResult
    func track(_ download: WKDownload, scope: DownloadScope, pageURL: URL?) -> DownloadItem {
        let item = DownloadItem(download: download, scope: scope, sourceURL: download.originalRequest?.url, pageURL: pageURL)
        download.delegate = self
        active[ObjectIdentifier(download)] = item
        item.observe(download.progress)
        insert(item)
        Logger.downloads.info("Téléchargement commencé (\(Self.origin(of: item), privacy: .public))")
        return item
    }

    /// Ajoute `item` en tête de la liste (primitive de `track`, utilisée telle quelle par les tests).
    func insert(_ item: DownloadItem) {
        items.insert(item, at: 0)
    }

    /// Bouton « Annuler » : le fichier partiel est effacé une fois WebKit arrêté.
    func cancel(_ item: DownloadItem) {
        guard item.isActive else {
            return
        }
        let download = item.download
        stopTracking(item)
        item.markCancelled()
        Logger.downloads.info("Téléchargement annulé (\(Self.origin(of: item), privacy: .public))")
        guard let download else {
            discardPartialFile(of: item)
            return
        }
        download.cancel { [weak self] _ in
            self?.discardPartialFile(of: item)
        }
    }

    /// « Effacer » : retire de la liste d'une fenêtre ce qui n'est plus en cours ; aucun fichier n'est effacé.
    func clear(in scope: DownloadScope) {
        items.removeAll { $0.scope == scope && !$0.isActive }
    }

    /// Fenêtre privée fermée : ses téléchargements en cours sont annulés (fichiers partiels effacés), ceux qui sont
    /// terminés restent dans Téléchargements, et tous quittent la liste.
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

    // MARK: Primitives du délégué WebKit (`+Delegate`)

    /// Place du fichier : un nom libre dans le dossier, réservé jusqu'à ce que le fichier existe ; nil si le dossier
    /// est introuvable (le téléchargement échoue).
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

    /// Le téléchargement n'est plus suivi par WebKit : plus de rappel attendu pour lui.
    func stopTracking(_ item: DownloadItem) {
        active = active.filter { $0.value !== item }
    }

    /// Un téléchargement de `scope` vient de se terminer.
    func recordFinish(in scope: DownloadScope) {
        finishedCounts[scope, default: 0] += 1
    }

    /// Libère le nom réservé par `item` : son fichier existe désormais, ou a été effacé.
    func releaseReservation(of item: DownloadItem) {
        if let name = item.destinationURL?.lastPathComponent {
            reservedNames.remove(Self.reservationKey(name))
        }
    }

    /// Efface le fichier partiel d'un téléchargement arrêté (jamais un autre : son nom était libre et réservé), puis
    /// libère son nom.
    func discardPartialFile(of item: DownloadItem) {
        if let destination = item.destinationURL, Self.itemExists(at: destination) {
            do {
                try FileManager.default.removeItem(at: destination)
            } catch {
                Logger.downloads.error("Fichier partiel non effacé : \(error.localizedDescription, privacy: .public)")
            }
        }
        releaseReservation(of: item)
    }

    /// Hôte de l'adresse demandée, ou son schéma (`data`, `blob`) : jamais l'adresse complète dans le journal.
    static func origin(of item: DownloadItem) -> String {
        item.sourceURL?.host() ?? item.sourceURL?.scheme ?? "?"
    }

    /// Fermeture de l'app : WebKit s'arrête avec elle, les fichiers partiels n'ont plus d'avenir.
    private func removePartialFiles() {
        for item in items where item.isActive {
            discardPartialFile(of: item)
        }
    }

    /// Vrai si quelque chose occupe ce chemin, lien symbolique cassé compris (`fileExists` le suivrait).
    private static func itemExists(at url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    private static func reservationKey(_ name: String) -> String {
        name.precomposedStringWithCanonicalMapping.lowercased()
    }
}
