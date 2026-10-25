import Foundation
@testable import Matcha
import Testing

/// Keeps the answers given to WebKit by permission requests (true: granted).
@MainActor
final class PermissionRecorder {
    private(set) var answers: [Bool] = []

    func response() -> PermissionResponse {
        PermissionResponse { [weak self] in self?.answers.append($0) }
    }
}

/// Origins for the permission tests.
nonisolated enum TestOrigins {
    static let meet = testOrigin("https", "meet.example.com")
    static let other = testOrigin("https", "other.example.org")
    static let local = testOrigin("http", "localhost", port: 8080)
}

@MainActor
extension SitePermissionRequest {
    /// Test request: `asked` defaults to `requested`.
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
