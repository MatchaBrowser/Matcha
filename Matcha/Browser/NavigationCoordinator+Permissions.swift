import OSLog
import WebKit

/// Site permissions (task 5.2): camera and microphone. A decision remembered for the profile answers at once;
/// otherwise the request waits in the banner of the page that made it (tab, Peek or mini window), with no timeout
/// and no automatic answer. The key is the origin of the main page; the banner names the requesting frame if it is
/// from another site. Location (macOS 27) and notifications: postponed, `DECISIONS.md`.
extension NavigationCoordinator {
    /// `origin` is that of the main page (WebKit header: “The origin of the page”), `frame` the frame whose script
    /// makes the request.
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
            // Unknown type: refused (empty request).
            []
        }
    }

    /// Entry point without WebKit types (testable): answers from the remembered decisions of the profile of `webView`,
    /// or puts the request in the banner of its page.
    func requestPermission(
        _ kinds: Set<SitePermissionKind>,
        origin: SiteOrigin?,
        frameOrigin: SiteOrigin?,
        in webView: WKWebView,
        response: PermissionResponse,
    ) {
        guard let tabHost, let page = tabHost.page(for: webView) else {
            Logger.permissions.notice("Request denied: unknown page")
            response.send(false)
            return
        }
        let scope = tabHost.sitePermissions(for: webView)
        let stored = origin.flatMap { scope?.decisions(for: $0) } ?? [:]
        let host = origin?.displayHost ?? "?"
        switch SitePermissionPolicy.evaluate(kinds, stored: stored) {
        case .grant:
            Logger.permissions.info("Request granted by a remembered decision (\(host, privacy: .private))")
            response.send(true)
        case .deny:
            Logger.permissions.info("Request denied by a remembered decision (\(host, privacy: .private))")
            response.send(false)
        case let .ask(asked):
            Logger.permissions.info("Request waiting in the banner (\(host, privacy: .private))")
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
