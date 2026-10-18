import AppKit
import WebKit

/// Un onglet tel que le voient les extensions (tâche 6.3) : adaptateur `WKWebExtensionTab` d'un `BrowserTab`, désigné par
/// son identifiant et relu à chaque question dans `ExtensionWindows` (un favori peut changer d'objet quand un Space en
/// reprend la copie). Un objet par onglet, toujours le même tant qu'il est ouvert : WebKit reconnaît les onglets à leur
/// objet. `BrowserTab` n'est pas un `NSObject` : il n'adopte pas le protocole lui-même. Actions : `+Actions`.
@MainActor
final class ExtensionTab: NSObject, WKWebExtensionTab {
    let tabID: UUID
    /// Fenêtre où l'onglet se trouve, ou se trouvait juste avant sa fermeture (événement `tabs.onRemoved`).
    var windowID: UUID?
    private(set) weak var windows: ExtensionWindows?

    init(id: UUID, windows: ExtensionWindows) {
        tabID = id
        self.windows = windows
    }

    /// L'onglet vivant ; nil une fois fermé.
    var page: BrowserTab? {
        windows?.liveTab(tabID)?.tab
    }

    var owner: ExtensionTabOwner? {
        windows?.liveTab(tabID)?.owner
    }

    func window(for _: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        guard let windowID, let windows else {
            return nil
        }
        return windows.windowAdapter(windowID)
    }

    func indexInWindow(for _: WKWebExtensionContext) -> Int {
        windows?.location(ofTab: tabID)?.index ?? NSNotFound
    }

    /// Onglet d'où celui-ci a été ouvert (lien, `window.open`), s'il est encore ouvert.
    func parentTab(for _: WKWebExtensionContext) -> (any WKWebExtensionTab)? {
        guard let windows, let openerID = page?.openerID, windows.location(ofTab: openerID) != nil else {
            return nil
        }
        return windows.tabAdapter(openerID)
    }

    /// Vue web de la page, si elle est chargée et branchée sur le contrôleur de cette extension (sinon WebKit la refuse).
    func webView(for context: WKWebExtensionContext) -> WKWebView? {
        guard let webView = page?.webView, let controller = context.webExtensionController,
              webView.configuration.webExtensionController === controller
        else {
            return nil
        }
        return webView
    }

    func title(for _: WKWebExtensionContext) -> String? {
        page?.title
    }

    /// Favoris et épinglés : toujours en tête de leur Space, comme les onglets épinglés de Chrome.
    func isPinned(for _: WKWebExtensionContext) -> Bool {
        windows?.state.tabs[tabID]?.isPinned ?? false
    }

    func isPlayingAudio(for _: WKWebExtensionContext) -> Bool {
        page?.isPlayingAudio ?? false
    }

    func zoomFactor(for _: WKWebExtensionContext) -> Double {
        page?.pageZoom ?? 1
    }

    /// Adresse de l'onglet, même déchargé ou en veille (sans vue web).
    func url(for _: WKWebExtensionContext) -> URL? {
        page?.url
    }

    /// Un onglet sans vue web (déchargé, en veille) est « complet ».
    func isLoadingComplete(for _: WKWebExtensionContext) -> Bool {
        !(page?.isLoading ?? false)
    }

    /// Panneaux du split affiché par sa fenêtre (l'onglet actif compris).
    func isSelected(for _: WKWebExtensionContext) -> Bool {
        windows?.isSelected(tabID) ?? false
    }
}
