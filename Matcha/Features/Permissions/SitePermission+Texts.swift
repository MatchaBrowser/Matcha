import Foundation

/// Texts and icons of site permissions (banner, site settings, Settings > Privacy).
extension SitePermissionKind {
    var title: String {
        switch self {
        case .camera:
            String(localized: "Camera", comment: "Website permission: the camera")
        case .microphone:
            String(localized: "Microphone", comment: "Website permission: the microphone")
        case .notifications:
            String(localized: "Notifications", comment: "Website permission: sending notifications")
        }
    }

    var symbolName: String {
        switch self {
        case .camera:
            "video"
        case .microphone:
            "mic"
        case .notifications:
            "bell"
        }
    }
}

extension SitePermissionDecision {
    /// State of a remembered decision, in the Settings list.
    var stateTitle: String {
        switch self {
        case .allow:
            String(localized: "Allowed", comment: "Settings > Privacy: a website is allowed to use the camera or microphone")
        case .deny:
            String(localized: "Denied", comment: "Settings > Privacy: a website is not allowed to use the camera or microphone")
        }
    }
}
