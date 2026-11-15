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
    /// The login field of the main frame the user just reached: the native list shows under it (`VAULT.md` § 8.1).
    var focusedField: VaultFieldPlace?
    /// The rows of that list while it shows some, given by the list: the keyboard moves in them.
    struct SuggestionRows {
        /// The list that gave them: only it takes them back.
        let owner: UUID
        let count: Int
        let choose: (Int) -> Void
    }

    @ObservationIgnored var suggestionRows: SuggestionRows?
    /// The row highlighted by ↓ and ↑, or under the pointer: what ↩ fills.
    var highlightedRow: Int?
    /// A private window: nothing is offered for saving without being asked (`VAULT.md` § 8.4).
    @ObservationIgnored var isPrivate = false
    /// The user name of a first step, whose password comes on the next page of the same origin: kept 10 minutes.
    private struct FirstStep {
        let origin: String
        let username: String
        let date: Date
    }

    @ObservationIgnored private var firstStep: FirstStep?
    static let firstStepLifetime: TimeInterval = 10 * 60

    /// The page has a field to fill.
    var hasLoginForm: Bool {
        frames.values.contains { $0.hasPassword || $0.hasUsername }
    }

    /// The main frame, when it has a field to fill.
    var mainFrame: Frame? {
        frames.values.first { $0.isMainFrame && ($0.hasPassword || $0.hasUsername) }
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
        switch message {
        case let .forms(hasPassword, hasUsername, isSignup):
            report(Frame(
                info: frame,
                origin: origin,
                url: url,
                isMainFrame: frame.isMainFrame,
                hasPassword: hasPassword,
                hasUsername: hasUsername,
                isSignup: isSignup,
            ))
        case let .submitted(username, password, isSignup):
            guard !isPrivate else {
                return
            }
            let username = username.isEmpty ? firstStepUsername(for: origin) ?? "" : username
            offer = SaveOffer(url: url, username: username, password: password, isSignup: isSignup)
        case let .username(username):
            guard !isPrivate else {
                return
            }
            firstStep = FirstStep(origin: origin, username: username, date: .now)
        case let .field(place):
            focus(place, from: frame)
        case .fieldDone:
            focus(nil, from: frame)
        }
    }

    /// What a frame now has; the main frame's report replaces the last one.
    private func report(_ frame: Frame) {
        let key = frame.isMainFrame ? "main" : "\(frame.origin)|\(frame.info.request.url?.absoluteString.prefix(200) ?? "")"
        if frame.isMainFrame {
            frames = frames.filter { !$0.value.isMainFrame }
        }
        if frame.hasPassword || frame.hasUsername {
            frames[key] = frame
        } else {
            frames[key] = nil
            focus(nil, from: frame.info)
        }
    }

    /// The field of the main frame under which the list shows; a frame's field never moves it.
    private func focus(_ place: VaultFieldPlace?, from frame: WKFrameInfo) {
        if frame.isMainFrame {
            focusedField = place
        }
    }

    /// ↓ and ↑ move in the rows (from none, to the first or the last), ↩ fills the highlighted one, ⎋ closes the list.
    /// Nothing is taken without rows, nor ↩ without a highlighted row: the form is then sent as usual.
    func takeSuggestionKey(_ key: VaultSuggestionKey) -> Bool {
        guard focusedField != nil, let rows = suggestionRows, rows.count >= 1 else {
            return false
        }
        switch key {
        case .next:
            highlightedRow = highlightedRow.map { min($0 + 1, rows.count - 1) } ?? 0
        case .previous:
            highlightedRow = highlightedRow.map { max($0 - 1, 0) } ?? rows.count - 1
        case .choose:
            guard let row = highlightedRow, row < rows.count else {
                return false
            }
            rows.choose(row)
        case .close:
            focusedField = nil
        }
        return true
    }

    /// The user name typed on the first step of a login on `origin`, if it was recent.
    private func firstStepUsername(for origin: String) -> String? {
        guard let firstStep, firstStep.origin == origin, Date.now.timeIntervalSince(firstStep.date) < Self.firstStepLifetime else {
            return nil
        }
        return firstStep.username
    }

    /// A new page in the main frame: its forms will be reported again.
    func pageChanged() {
        frames = [:]
        focusedField = nil
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
