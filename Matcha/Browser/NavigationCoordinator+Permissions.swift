import OSLog
import WebKit

/// Permissions des sites (tâche 5.2) : caméra et micro. Une décision retenue pour le profil répond aussitôt ; sinon
/// la demande attend dans le bandeau de la page qui l'a faite (onglet, aperçu ou mini-fenêtre), sans délai ni
/// réponse automatique. La clé est l'origine de la page principale ; le bandeau nomme le cadre qui demande s'il est
/// d'un autre site. Localisation (macOS 27) et notifications : reportées, `DECISIONS.md`.
extension NavigationCoordinator {
    /// `origin` est celle de la page principale (en-tête de WebKit : « The origin of the page »), `frame` le cadre
    /// dont le script demande.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void,
    ) {
        let frameOrigin = frame.securityOrigin
        requestPermission(
            Self.kinds(of: type),
            origin: SiteOrigin(scheme: origin.protocol, host: origin.host, port: origin.port),
            frameOrigin: SiteOrigin(scheme: frameOrigin.protocol, host: frameOrigin.host, port: frameOrigin.port),
            in: webView,
            response: PermissionResponse { decisionHandler($0 ? .grant : .deny) },
        )
    }

    static func kinds(of type: WKMediaCaptureType) -> Set<SitePermissionKind> {
        switch type {
        case .camera:
            [.camera]
        case .microphone:
            [.microphone]
        case .cameraAndMicrophone:
            [.camera, .microphone]
        @unknown default:
            // Type inconnu : refusé (demande vide).
            []
        }
    }

    /// Point d'entrée sans types WebKit (testable) : répond d'après les décisions retenues du profil de `webView`,
    /// ou met la demande dans le bandeau de sa page.
    func requestPermission(
        _ kinds: Set<SitePermissionKind>,
        origin: SiteOrigin?,
        frameOrigin: SiteOrigin?,
        in webView: WKWebView,
        response: PermissionResponse,
    ) {
        guard let tabHost, let page = tabHost.page(for: webView) else {
            Logger.permissions.notice("Demande refusée : page inconnue")
            response.send(false)
            return
        }
        let scope = tabHost.sitePermissions(for: webView)
        let stored = origin.flatMap { scope?.decisions(for: $0) } ?? [:]
        let host = origin?.displayHost ?? "?"
        switch SitePermissionPolicy.evaluate(kinds, stored: stored) {
        case .grant:
            Logger.permissions.info("Demande accordée par une décision retenue (\(host, privacy: .private))")
            response.send(true)
        case .deny:
            Logger.permissions.info("Demande refusée par une décision retenue (\(host, privacy: .private))")
            response.send(false)
        case let .ask(asked):
            Logger.permissions.info("Demande en attente dans le bandeau (\(host, privacy: .private))")
            page.permissionPrompts.enqueue(SitePermissionRequest(
                origin: origin,
                frameName: frameOrigin.flatMap { $0 == origin ? nil : $0.displayName },
                requested: kinds,
                asked: asked,
                scope: scope,
                response: response,
            ))
        }
    }
}
