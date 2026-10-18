import AppKit
import Observation

/// Capture posée sur une page sortie de veille, le temps de son rechargement.
struct TabCover {
    let image: NSImage
    /// Largeur de la page capturée, en points.
    let pageWidth: Double
}

/// Mise en veille d'un onglet pour libérer sa mémoire (tâche 5.6, `TabLifecycleService`). En veille, l'onglet n'a plus
/// de vue web mais garde son adresse, son titre, son icône et son état de navigation : la barre latérale l'affiche comme
/// avant, et il se recrée quand on l'affiche. Sa capture, prise avant la veille, couvre alors la page recréée le temps
/// de son premier chargement, au plus `coverDuration` ; pendant ce rechargement, un titre vide ou une adresse absente de
/// la vue web neuve ne remplacent pas ceux de l'onglet.
@MainActor
@Observable
final class TabSuspension {
    /// Durée maximale de la capture par-dessus la page recréée : au-delà, la page se montre même en cours de chargement.
    static let coverDuration = Duration.seconds(2)
    /// Fin du rechargement sans réponse de la page : le titre et l'adresse suivent de nouveau la vue web.
    static let restoreTimeout = Duration.seconds(10)

    /// Page suivie : relue à la fin du rechargement.
    @ObservationIgnored weak var page: BrowserTab?
    /// Vrai pendant la veille.
    private(set) var isSuspended = false
    /// Capture montrée par-dessus la page recréée, tant qu'elle n'est pas chargée.
    private(set) var cover: TabCover?
    /// Capture gardée pendant la veille.
    @ObservationIgnored private(set) var snapshot: TabSnapshot?
    /// Moment de la mise en veille (les captures les plus anciennes partent les premières).
    @ObservationIgnored private(set) var suspendedAt: Date?
    /// Vrai de la recréation de la vue jusqu'à la fin de son premier chargement.
    @ObservationIgnored private(set) var isRestoring = false
    /// Adresse de la page capturée qui couvre la page recréée.
    @ObservationIgnored private var coverURL: URL?
    @ObservationIgnored private var restoreTask: Task<Void, Never>?

    /// La vue web vient d'être libérée.
    func didSuspend(snapshot: TabSnapshot?, at date: Date) {
        reset()
        isSuspended = true
        self.snapshot = snapshot
        suspendedAt = date
    }

    /// La vue web est recréée pour afficher `url` : la capture la couvre si elle montre cette adresse.
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

    /// L'adresse de la page recréée a changé : une capture d'une autre page ne la couvre plus.
    func pageURLDidChange(to url: URL?) {
        if let url, url != coverURL {
            dropCover()
        }
    }

    /// Premier chargement terminé ou échoué, autre navigation demandée : la capture part, l'onglet suit la vue web.
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

    /// Le service garde un nombre limité de captures : celle-ci part, la veille continue.
    func discardSnapshot() {
        snapshot = nil
    }

    /// Onglet déchargé, ramené à une autre adresse ou fermé : plus de veille ni de capture. Les valeurs observées ne
    /// sont écrites que si elles changent : la barre latérale n'est pas redessinée pour rien.
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

    /// Retire la capture de la page ; la valeur observée n'est écrite que si elle change.
    private func dropCover() {
        if cover != nil {
            cover = nil
        }
        coverURL = nil
    }
}
