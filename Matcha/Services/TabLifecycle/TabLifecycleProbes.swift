import AppKit
import WebKit

/// Ce que la mise en veille demande à WebKit (tâche 5.6), remplaçable dans les tests : le son, et la capture de la
/// page. Les deux sont asynchrones ; sans réponse à temps, la page est tenue pour occupée (pas de veille) ou sans
/// capture.
@MainActor
struct TabLifecycleProbes {
    /// Délai de réponse de WebKit : une page qui ne répond pas joue peut-être du son.
    static let timeout = Duration.seconds(2)

    /// Vrai si la page joue un média, ou si WebKit n'a pas répondu à temps.
    var isPlayingMedia: @MainActor (WKWebView) async -> Bool
    /// Capture de la page affichée par la vue (son adresse est donnée à part), ou nil.
    var snapshot: @MainActor (WKWebView, URL?) async -> TabSnapshot?

    static let webKit = TabLifecycleProbes(isPlayingMedia: isPlayingMedia(in:), snapshot: snapshot(of:url:))

    /// `requestMediaPlaybackState` : seul « en lecture » compte (une vidéo en pause peut se décharger). Prudent :
    /// vérifié (tâche 5.10), WebKit répond « en lecture » dès qu'un média de la page n'est pas en pause, même chargé
    /// mais jamais lancé ou coupé (Web Audio et `new Audio()` compris), et « en pause » dès qu'un seul l'est.
    static func isPlayingMedia(in webView: WKWebView) async -> Bool {
        await CallbackTimeout.value(timeout: timeout, fallback: true) { done in
            webView.requestMediaPlaybackState { state in
                done(state == .playing)
            }
        }
    }

    /// `takeSnapshot` de la partie visible de la page, sans attendre une mise à jour de l'écran : la vue d'un onglet
    /// caché n'est dans aucune fenêtre (WebKit dessine quand même la page). Rien pour une vue sans taille (onglet
    /// ouvert en arrière-plan, jamais affiché).
    static func snapshot(of webView: WKWebView, url: URL?) async -> TabSnapshot? {
        let width = webView.bounds.width
        guard width >= 1, webView.bounds.height >= 1 else {
            return nil
        }
        let configuration = WKSnapshotConfiguration()
        configuration.afterScreenUpdates = false
        let data = await CallbackTimeout.value(timeout: timeout, fallback: nil as Data?) { done in
            webView.takeSnapshot(with: configuration) { image, _ in
                done(image?.cgImage(forProposedRect: nil, context: nil, hints: nil).flatMap { TabSnapshot.jpegData(from: $0) })
            }
        }
        return data.map { TabSnapshot(data: $0, url: url, pageWidth: width) }
    }
}
