import Foundation

/// Sound of a page (task 5.10), from the messages of its script (`PageAudioReport`). The speaker icon lights up as soon
/// as a document of the page (main frame or iframe) plays a sound, and switches off `silenceDelay` (2 s) after the last
/// one: no flicker between two tracks, an ad and the video, or during a source change (like Chrome). It switches off
/// right away (`reset`) when the user pauses the page, when the page changes (navigation), is put to sleep or its
/// process stops.
nonisolated struct PageAudioState: Equatable, Sendable {
    static let defaultSilenceDelay: TimeInterval = 2

    /// Delay between the end of the last sound and the switch-off of the icon; changed in tests.
    var silenceDelay = defaultSilenceDelay
    /// Documents playing a sound.
    private(set) var audibleFrames: Set<String> = []
    /// Icon displayed.
    private(set) var isPlaying = false
    /// Moment the last sound stopped, as long as the icon stays on.
    private(set) var silentSince: Date?

    /// Moment the icon must switch off; nil if nothing is scheduled.
    var silenceDeadline: Date? {
        silentSince.map { $0.addingTimeInterval(silenceDelay) }
    }

    /// A document reports that it plays a sound, no longer plays one, or goes away.
    mutating func apply(_ report: PageAudioReport, at date: Date) {
        if report.isAudible, !report.isGone {
            audibleFrames.insert(report.frame)
        } else {
            audibleFrames.remove(report.frame)
        }
        if !audibleFrames.isEmpty {
            isPlaying = true
            silentSince = nil
        } else if isPlaying, silentSince == nil {
            silentSince = date
        }
    }

    /// The icon switches off if nothing has played for `silenceDelay` at `date`.
    mutating func expire(at date: Date) {
        guard let silenceDeadline, date >= silenceDeadline else {
            return
        }
        isPlaying = false
        silentSince = nil
    }

    /// No sound anymore: everything is paused, or the page changed. A document that plays a sound again says so.
    mutating func reset() {
        audibleFrames = []
        isPlaying = false
        silentSince = nil
    }
}
