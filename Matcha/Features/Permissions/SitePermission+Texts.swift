import Foundation

/// Textes et icônes des permissions des sites (bandeau, réglages du site, Réglages > Confidentialité).
extension SitePermissionKind {
    var title: String {
        switch self {
        case .camera:
            String(localized: "Camera", comment: "Website permission: the camera")
        case .microphone:
            String(localized: "Microphone", comment: "Website permission: the microphone")
        }
    }

    var symbolName: String {
        switch self {
        case .camera:
            "video"
        case .microphone:
            "mic"
        }
    }
}

extension SitePermissionDecision {
    /// État d'une décision retenue, dans la liste des Réglages.
    var stateTitle: String {
        switch self {
        case .allow:
            String(localized: "Allowed", comment: "Settings > Privacy: a website is allowed to use the camera or microphone")
        case .deny:
            String(localized: "Denied", comment: "Settings > Privacy: a website is not allowed to use the camera or microphone")
        }
    }
}
