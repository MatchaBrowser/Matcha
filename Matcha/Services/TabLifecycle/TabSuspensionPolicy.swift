import Foundation

/// An open tab, as tab sleeping sees it.
nonisolated struct TabLifecycleCandidate: Equatable, Sendable {
    let id: UUID
    /// Moment the tab left the screen; nil if it is displayed.
    let hiddenSince: Date?
    /// Web view present: otherwise there is nothing to release (tab never displayed since launch, already asleep).
    let isLoaded: Bool
    /// Permission banner waiting for an answer (task 5.2).
    let hasPendingPermissionPrompt: Bool
    /// Camera or microphone in use (even muted).
    let isCapturingMedia: Bool
    /// Sound playing according to the page's script (speaker icon, task 5.10): busy, without waiting for WebKit.
    let isPlayingAudio: Bool
    /// Sign-in window opened by the page, still open (task 5.8): asleep, the page would no longer be its
    /// `window.opener`, and the sign-in would fail.
    let hasOpenPopupWindow: Bool
    /// The displayed website may send notifications: asleep, it could no longer send any.
    var canSendNotifications = false
}

/// What triggers a check.
nonisolated enum TabSuspensionReason: String, Sendable {
    /// Regular check: tabs hidden for longer than the configured delay.
    case inactivity
    /// System memory warning: the oldest half of the hidden tabs.
    case memoryWarning
    /// Critical memory warning: all hidden tabs.
    case memoryCritical
}

/// Rules of tab sleeping (task 5.6). Never: a displayed tab (all the panes of a split, the originating tab of a Peek),
/// one without a web view, one waiting for a permission answer, one using the camera or the microphone, one that opened
/// a sign-in window that is still open (task 5.8), one whose website may send notifications, or one playing sound:
/// according to its speaker icon (task 5.10), otherwise checked afterwards with WebKit. “Never” in the settings:
/// nothing, even during a memory warning.
nonisolated enum TabSuspensionPolicy {
    /// During a simple warning, a tab hidden for a shorter time is spared: people often go back to the tab they just
    /// left.
    static let warningMinimumHiddenTime: TimeInterval = 60

    static func isEligible(_ candidate: TabLifecycleCandidate) -> Bool {
        candidate.hiddenSince != nil && candidate.isLoaded && !candidate.hasPendingPermissionPrompt && !candidate.isCapturingMedia
            && !candidate.isPlayingAudio && !candidate.hasOpenPopupWindow && !candidate.canSendNotifications
    }

    /// Tabs to examine, from the one hidden longest ago to the most recent; `delay` nil (“Never”): none. Sound that the
    /// icon does not show (Web Audio, element outside the page) is checked afterwards, on these tabs only.
    static func pool(_ candidates: [TabLifecycleCandidate], reason: TabSuspensionReason, delay: TimeInterval?, now: Date) -> [UUID] {
        guard let delay else {
            return []
        }
        let minimumHiddenTime: TimeInterval? = switch reason {
        case .inactivity: delay
        case .memoryWarning: warningMinimumHiddenTime
        case .memoryCritical: nil
        }
        return candidates
            .compactMap { candidate -> (id: UUID, hiddenSince: Date)? in
                guard isEligible(candidate), let hiddenSince = candidate.hiddenSince else {
                    return nil
                }
                if let minimumHiddenTime, now.timeIntervalSince(hiddenSince) < minimumHiddenTime {
                    return nil
                }
                return (candidate.id, hiddenSince)
            }
            .sorted { ($0.hiddenSince, $0.id.uuidString) < ($1.hiddenSince, $1.id.uuidString) }
            .map(\.id)
    }

    /// Among the examined tabs that are not playing sound (in the order of `pool`), those to put to sleep: the oldest
    /// half (rounded up) during a simple warning, otherwise all of them.
    static func limit(_ idle: [UUID], reason: TabSuspensionReason) -> [UUID] {
        reason == .memoryWarning ? Array(idle.prefix((idle.count + 1) / 2)) : idle
    }
}

nonisolated extension Duration {
    /// Duration in seconds, for date comparisons.
    var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
