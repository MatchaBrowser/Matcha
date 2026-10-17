import Foundation
import Observation
import WebKit

/// Étape d'un téléchargement.
nonisolated enum DownloadState: Equatable, Sendable {
    case downloading
    case finished
    case failed
    case cancelled
}

/// Fenêtre d'où part un téléchargement : chaque fenêtre de navigation montre les siens. Ceux d'une fenêtre privée
/// quittent la liste à sa fermeture ; ceux des mini-fenêtres vont avec la fenêtre principale.
nonisolated enum DownloadScope: Hashable, Sendable {
    case regular
    case privateWindow(UUID)
}

/// Un téléchargement de cette session de l'app, tel que la liste l'affiche. L'objet WebKit (`WKDownload`) et le
/// suivi de sa progression ne vivent que le temps du téléchargement.
@MainActor
@Observable
final class DownloadItem: Identifiable {
    /// Intervalle minimal entre deux mises à jour de la progression : WebKit la signale à chaque paquet reçu.
    static let progressInterval = Duration.milliseconds(100)

    let id = UUID()
    let scope: DownloadScope
    /// Adresse demandée (avant redirection).
    let sourceURL: URL?
    /// Page d'où part le téléchargement, pour l'attribut de quarantaine.
    let pageURL: URL?
    /// Nom affiché : celui du fichier une fois sa place choisie, sinon le dernier composant de l'adresse.
    private(set) var fileName: String
    /// Fichier écrit dans Téléchargements ; nil tant que sa place n'est pas choisie.
    private(set) var destinationURL: URL?
    private(set) var state = DownloadState.downloading
    private(set) var completedBytes: Int64 = 0
    /// Taille annoncée par le serveur ; nil si elle est inconnue.
    private(set) var totalBytes: Int64?
    /// Raison d'un échec, dans la langue de l'utilisateur.
    private(set) var failureReason: String?

    /// Téléchargement WebKit, retenu tant qu'il est en cours.
    @ObservationIgnored private(set) var download: WKDownload?
    @ObservationIgnored private var progressObservation: NSKeyValueObservation?
    @ObservationIgnored private var lastProgressUpdate: ContinuousClock.Instant?

    init(download: WKDownload?, scope: DownloadScope, sourceURL: URL?, pageURL: URL?) {
        self.download = download
        self.scope = scope
        self.sourceURL = sourceURL
        self.pageURL = pageURL
        fileName = DownloadFileName.make(suggested: nil, url: sourceURL, mimeType: nil)
    }

    var isActive: Bool {
        state == .downloading
    }

    /// Part reçue, de 0 à 1 ; nil si la taille est inconnue.
    var fractionCompleted: Double? {
        DownloadProgressSummary.fraction(completed: completedBytes, total: totalBytes)
    }

    /// Place choisie : le nom affiché devient celui du fichier.
    func setDestination(_ url: URL) {
        destinationURL = url
        fileName = url.lastPathComponent
    }

    /// Suit `progress` (celle de `WKDownload`) jusqu'à la fin du téléchargement.
    func observe(_ progress: Progress) {
        update(from: progress, force: true)
        progressObservation = progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            Self.onMain {
                self?.update(from: progress, force: false)
            }
        }
    }

    /// Fin réussie : la taille est celle du fichier écrit.
    func markFinished(size: Int64?) {
        stopObserving()
        let size = size ?? completedBytes
        completedBytes = size
        totalBytes = size
        state = .finished
    }

    func markFailed(reason: String?) {
        stopObserving()
        failureReason = reason
        state = .failed
    }

    func markCancelled() {
        stopObserving()
        state = .cancelled
    }

    /// Recopie la progression, au plus toutes les `progressInterval` (sauf au début et à la fin).
    private func update(from progress: Progress, force: Bool) {
        guard isActive else {
            return
        }
        let now = ContinuousClock.now
        let total = progress.totalUnitCount
        let completed = progress.completedUnitCount
        if !force, total <= 0 || completed < total, let lastProgressUpdate, now - lastProgressUpdate < Self.progressInterval {
            return
        }
        lastProgressUpdate = now
        completedBytes = max(0, completed)
        totalBytes = total > 0 ? total : nil
    }

    private func stopObserving() {
        progressObservation = nil
        download = nil
    }

    /// WebKit signale la progression sur le fil principal ; par prudence, un appel venu d'ailleurs y est renvoyé.
    private nonisolated static func onMain(_ body: @escaping @MainActor @Sendable () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(body)
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }
}
