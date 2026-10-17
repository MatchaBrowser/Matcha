import AppKit
import WebKit

/// Ce qu'il faut savoir d'une demande de navigation pour décider quoi en faire.
nonisolated struct NavigationRequest: Sendable {
    var url: URL?
    var navigationType: WKNavigationType
    var modifierFlags: NSEvent.ModifierFlags
    /// Boutons de la souris, en masque (vérifié avec WebKit) : 1 gauche (et Entrée sur un lien), 2 droit,
    /// 4 milieu, 0 aucun (clic simulé par la page).
    var buttonNumber: Int
    /// Vrai si la navigation vise le cadre principal ou une nouvelle fenêtre, faux pour un cadre secondaire.
    var targetsMainFrame: Bool
    /// Vrai si la vue web sait charger ce schéma (http, https, about, data, blob, schéma enregistré…).
    var isSchemeHandledByWebView: Bool
    /// Vrai si la navigation demande une nouvelle fenêtre (`target=_blank`, `window.open`) : pas de cadre cible.
    var opensNewWindow = false
    /// Adresse de la page affichée par la vue web : ancre de la même page, lien vers un autre site.
    var pageURL: URL?
    /// Vrai si la page demande le téléchargement (lien `download`) : la navigation devient un téléchargement.
    var shouldPerformDownload = false
    /// Vue web d'où part la navigation.
    var source = NavigationSource.tab
    /// Vrai si les liens vers un autre site s'ouvrent dans l'aperçu : favori ou épinglé, réglage activé.
    var opensOtherSitesInPeek = false
}

/// Vue web d'où part une navigation.
nonisolated enum NavigationSource: Sendable {
    /// Un onglet de la barre latérale.
    case tab
    /// L'aperçu (Peek, tâche 4.4).
    case peek
    /// Une vue web que ce gestionnaire d'onglets n'affiche pas, ou la page d'une mini-fenêtre (tâche 4.5) : un
    /// Maj+clic y reste un clic.
    case other
}

/// Issue d'une demande de navigation.
nonisolated enum NavigationDecision: Equatable, Sendable {
    /// WebKit poursuit la navigation.
    case allow
    /// La navigation est annulée sans autre effet.
    case cancel
    /// Annulée, puis l'URL est confiée à l'app qui la gère (Mail, Téléphone, Zoom…).
    case openExternally(URL)
    /// Annulée, puis l'URL est ouverte dans un nouvel onglet.
    case openInNewTab(URL, inBackground: Bool)
    /// Annulée, puis l'URL est ouverte dans l'aperçu ; depuis l'aperçu, elle s'y charge (tâche 4.4).
    case openInPeek(URL)
    /// La navigation devient un téléchargement (tâche 5.1).
    case download
}

/// Règles de navigation des vues web, sans dépendance à l'interface.
nonisolated enum NavigationPolicy {
    static let leftMouseButton = 1
    static let middleMouseButton = 4
    /// Schémas jamais ouverts en aperçu : leur contenu dépend de la page qui les contient.
    static let schemesKeptInPlace: Set<String> = ["about", "blob", "data", "javascript"]
    private static let linkModifiers: NSEvent.ModifierFlags = [.shift, .command, .option, .control]

    static func decide(_ request: NavigationRequest) -> NavigationDecision {
        guard let url = request.url else {
            return .allow
        }
        if !request.isSchemeHandledByWebView {
            // Un cadre secondaire (publicité…) n'a pas le droit de lancer une autre app.
            return request.targetsMainFrame ? .openExternally(url) : .cancel
        }
        // Lien `download` : téléchargé quel que soit le clic (⌘-clic, Maj+clic) ; un onglet ou un aperçu resterait vide.
        if request.shouldPerformDownload {
            return .download
        }
        guard request.navigationType == .linkActivated else {
            return .allow
        }
        let modifiers = request.modifierFlags.intersection(linkModifiers)
        if modifiers.contains(.command) || request.buttonNumber == middleMouseButton {
            return .openInNewTab(url, inBackground: !modifiers.contains(.shift))
        }
        guard !schemesKeptInPlace.contains(url.scheme?.lowercased() ?? "") else {
            return .allow
        }
        switch request.source {
        case .peek:
            // Dans l'aperçu, on parcourt sur place, même un lien qui ouvrirait une fenêtre.
            return request.opensNewWindow ? .openInPeek(url) : .allow
        case .other:
            return .allow
        case .tab:
            return peekDecision(for: request, url: url, modifiers: modifiers)
        }
    }

    /// Maj+clic (sauf ancre de la page affichée), et lien d'un favori ou d'un épinglé vers un autre site si le
    /// réglage le demande (clic gauche sans touche : jamais un clic simulé par la page).
    private static func peekDecision(for request: NavigationRequest, url: URL, modifiers: NSEvent.ModifierFlags) -> NavigationDecision {
        if modifiers == .shift {
            return isAnchorOfShownPage(url, request) ? .allow : .openInPeek(url)
        }
        guard modifiers.isEmpty, request.buttonNumber == leftMouseButton, request.opensOtherSitesInPeek,
              request.targetsMainFrame, let page = request.pageURL, SiteDomain.isCrossSite(from: page, to: url)
        else {
            return .allow
        }
        return .openInPeek(url)
    }

    private static func isAnchorOfShownPage(_ url: URL, _ request: NavigationRequest) -> Bool {
        guard !request.opensNewWindow, request.targetsMainFrame, url.fragment != nil, let page = request.pageURL else {
            return false
        }
        return removingFragment(url) == removingFragment(page)
    }

    private static func removingFragment(_ url: URL) -> URL? {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.fragment = nil
        return components?.url
    }
}
