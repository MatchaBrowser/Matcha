import Foundation
import Observation
import WebKit

/// The login forms of a tab's page, as the vault's script reports them (`VAULT.md` § 8): which frames can be filled,
/// with their origin as WebKit gives it (`WKFrameInfo.securityOrigin`, never the tab's address), and the login just
/// sent, to offer saving. Nothing here is filled: the interface asks, after a user action.
@MainActor
@Observable
final class VaultPageForms: VaultFormReceiving {
    /// A frame with a form: where to fill, and its origin.
    struct Frame {
        let info: WKFrameInfo
        /// `scheme://host[:port]`, from the frame's security origin.
        let origin: String
        let url: URL
        let isMainFrame: Bool
        var hasPassword: Bool
        var hasUsername: Bool
        var isSignup: Bool
    }

    /// A login just sent: offered to the vault.
    struct SaveOffer: Equatable {
        let url: URL
        let username: String
        let password: String
        let isSignup: Bool
    }

    private(set) var frames: [String: Frame] = [:]
    var offer: SaveOffer?
    /// A private window: nothing is offered for saving without being asked (`VAULT.md` § 8.4).
    @ObservationIgnored var isPrivate = false

    /// The page has a field to fill.
    var hasLoginForm: Bool {
        frames.values.contains { $0.hasPassword || $0.hasUsername }
    }

    /// The frames to fill, the main one first.
    var fillableFrames: [Frame] {
        frames.values.filter { $0.hasPassword || $0.hasUsername }.sorted { $0.isMainFrame && !$1.isMainFrame }
    }

    func receive(_ message: VaultFormMessage, from frame: WKFrameInfo) {
        guard let origin = Self.origin(of: frame), let url = URL(string: origin) else {
            // An opaque origin (sandboxed frame, data:): never filled.
            return
        }
        let key = frame.isMainFrame ? "main" : "\(origin)|\(frame.request.url?.absoluteString.prefix(200) ?? "")"
        switch message {
        case let .forms(hasPassword, hasUsername, isSignup):
            if frame.isMainFrame {
                frames = frames.filter { !$0.value.isMainFrame }
            }
            if hasPassword || hasUsername {
                frames[key] = Frame(
                    info: frame,
                    origin: origin,
                    url: url,
                    isMainFrame: frame.isMainFrame,
                    hasPassword: hasPassword,
                    hasUsername: hasUsername,
                    isSignup: isSignup,
                )
            } else {
                frames[key] = nil
            }
        case let .submitted(username, password, isSignup):
            guard !isPrivate else {
                return
            }
            offer = SaveOffer(url: url, username: username, password: password, isSignup: isSignup)
        }
    }

    /// A new page in the main frame: its forms will be reported again.
    func pageChanged() {
        frames = [:]
    }

    /// `scheme://host[:port]` of a frame's security origin; nil for an opaque one.
    static func origin(of frame: WKFrameInfo) -> String? {
        let origin = frame.securityOrigin
        guard ["http", "https"].contains(origin.protocol), !origin.host.isEmpty else {
            return nil
        }
        let isDefaultPort = origin
            .port == 0 || (origin.protocol == "https" && origin.port == 443) || (origin.protocol == "http" && origin.port == 80)
        let host = origin.host.contains(":") ? "[\(origin.host)]" : origin.host
        return isDefaultPort ? "\(origin.protocol)://\(host)" : "\(origin.protocol)://\(host):\(origin.port)"
    }
}
