import AppKit
import OSLog
import WebKit

/// Ce qu'une extension peut faire d'un onglet (tâche 6.3). Non pris en charge (erreur de WebKit « not implemented ») :
/// couper le son (aucune API publique), mode lecture, sélection multiple hors des splits (`setSelected`), changer
/// d'onglet parent.
extension ExtensionTab {
    typealias Completion = @Sendable ((any Error)?) -> Void

    /// Une page web, ou une page de la même extension : WebKit refuse de passer de l'une à l'autre dans la même vue web
    /// (`WKWebExtensionContext.webViewConfiguration`) ; ces pages s'ouvrent dans un nouvel onglet (`FEATURES.md`).
    func loadURL(_ url: URL, for _: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page, let owner else {
            completionHandler(ExtensionError.notFound)
            return
        }
        guard ExtensionManager.isExtensionURL(url) == ExtensionManager.isExtensionURL(page.url) else {
            completionHandler(ExtensionError.unsupported("An extension page and a webpage cannot replace each other in a tab."))
            return
        }
        page.load(url)
        if case let .miniWindow(controller, _) = owner {
            controller.showWebView()
        }
        completionHandler(nil)
    }

    /// Recharge la page ; un onglet sans vue web (déchargé, en veille) la recrée, ce qui la recharge.
    func reload(fromOrigin: Bool, for _: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page else {
            completionHandler(ExtensionError.notFound)
            return
        }
        if let webView = page.webView, fromOrigin {
            webView.reloadFromOrigin()
        } else if page.webView != nil {
            page.reload()
        } else {
            page.makeWebViewIfNeeded()
        }
        completionHandler(nil)
    }

    func goBack(for _: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page, page.canGoBack else {
            completionHandler(ExtensionError.unsupported("The tab cannot go back."))
            return
        }
        page.goBack()
        completionHandler(nil)
    }

    func goForward(for _: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page, page.canGoForward else {
            completionHandler(ExtensionError.unsupported("The tab cannot go forward."))
            return
        }
        page.goForward()
        completionHandler(nil)
    }

    /// Comme un clic dans la barre, sans prendre le clavier : la fenêtre affiche le Space de l'onglet, l'aperçu se ferme
    /// et l'onglet est sélectionné. L'aperçu, la page d'une mini-fenêtre ou d'une fenêtre de connexion sont toujours
    /// actifs.
    func activate(for _: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page, let owner else {
            completionHandler(ExtensionError.notFound)
            return
        }
        if case let .space(space, model) = owner {
            if model.space !== space {
                model.select(space)
            }
            space.tabManager.closePeek()
            space.tabManager.select(page)
        }
        windows?.update()
        completionHandler(nil)
    }

    /// Comme ⌘W : un onglet du jour se ferme ; un épinglé ou un favori revient à son adresse d'origine et se décharge,
    /// mais reste dans la barre (comme dans Arc) ; l'aperçu se ferme ; la page d'une mini-fenêtre ou d'une fenêtre de
    /// connexion ferme celle-ci.
    func close(for _: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page, let owner else {
            completionHandler(ExtensionError.notFound)
            return
        }
        switch owner {
        case let .space(space, _):
            space.tabManager.close(page)
        case let .peek(space, _):
            PeekActions.close(in: space.tabManager)
        case let .miniWindow(controller, _):
            controller.close()
        case let .popupWindow(controller, _):
            controller.close()
        }
        windows?.update()
        completionHandler(nil)
    }

    /// Épingler range l'onglet du jour à la fin des épinglés ; désépingler (un épinglé ou un favori) le remet en tête
    /// des onglets du jour, comme le menu de la barre.
    func setPinned(_ pinned: Bool, for context: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page, case let .space(space, _) = owner else {
            completionHandler(ExtensionError.unsupported("Only tabs of a browser window can be pinned."))
            return
        }
        if pinned != isPinned(for: context) {
            space.tabManager.setPlace(page, to: pinned ? .pinned : .today)
        }
        windows?.update()
        completionHandler(nil)
    }

    /// Zoom du site de la page, comme ⌘+ et ⌘- (tâche 5.4) : toutes les pages ouvertes de ce site le prennent, comme
    /// la portée « per-origin » de Chrome.
    func setZoomFactor(_ zoomFactor: Double, for _: WKWebExtensionContext, completionHandler: @escaping Completion) {
        guard let page else {
            completionHandler(ExtensionError.notFound)
            return
        }
        if let siteZooms = owner?.siteZooms {
            siteZooms.setZoom(zoomFactor, for: page)
        } else {
            page.setPageZoom(ZoomLevels.clamped(zoomFactor))
        }
        completionHandler(nil)
    }

    /// Comme « Dupliquer » de la barre : la copie, avec son historique, s'ouvre juste après l'onglet ; elle n'est active
    /// que si l'extension le demande.
    func duplicate(
        using configuration: WKWebExtension.TabConfiguration,
        for _: WKWebExtensionContext,
        completionHandler: @escaping @Sendable ((any WKWebExtensionTab)?, (any Error)?) -> Void,
    ) {
        guard let page, case let .space(space, _) = owner else {
            completionHandler(nil, ExtensionError.unsupported("Only tabs of a browser window can be duplicated."))
            return
        }
        let copy = space.tabManager.duplicate(page)
        if !configuration.shouldBeActive {
            space.tabManager.select(page)
        }
        windows?.update()
        completionHandler(windows?.adapter(for: copy), nil)
    }
}
