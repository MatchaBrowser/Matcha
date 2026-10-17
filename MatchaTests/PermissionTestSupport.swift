import Foundation
@testable import Matcha

/// Garde les réponses données à WebKit par les demandes de permission (vrai : accordé).
@MainActor
final class PermissionRecorder {
    private(set) var answers: [Bool] = []

    func response() -> PermissionResponse {
        PermissionResponse { [weak self] in self?.answers.append($0) }
    }
}

/// Origines des tests de permission.
nonisolated enum TestOrigins {
    static let meet = SiteOrigin(scheme: "https", host: "meet.example.com", port: nil)!
    static let other = SiteOrigin(scheme: "https", host: "other.example.org", port: nil)!
    static let local = SiteOrigin(scheme: "http", host: "localhost", port: 8080)!
}

extension SitePermissionRequest {
    /// Demande de test : `asked` vaut `requested` par défaut.
    @MainActor
    static func test(
        _ requested: Set<SitePermissionKind>,
        origin: SiteOrigin? = TestOrigins.meet,
        asked: Set<SitePermissionKind>? = nil,
        scope: SitePermissionScope?,
        response: PermissionResponse,
    ) -> SitePermissionRequest {
        SitePermissionRequest(
            origin: origin,
            frameName: nil,
            requested: requested,
            asked: asked ?? requested,
            scope: scope,
            response: response,
        )
    }
}
