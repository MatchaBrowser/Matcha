import Foundation
import Observation

/// Sound of a page (tab, Peek, mini window, sign-in window; task 5.10): receives the messages of its script
/// (`PageAudioMessageHandler`) and drives the speaker icon of the sidebar (`isPlaying`), following the rules of
/// `PageAudioState`. Only a page placed in the sidebar shows the icon; Peek opened as a tab keeps its state.
@MainActor
@Observable
final class PageAudio {
    /// True while the page plays a sound, and for `silenceDelay` afterwards.
    private(set) var isPlaying = false
    @ObservationIgnored private var state = PageAudioState()
    /// Scheduled switch-off of the icon.
    @ObservationIgnored private var expiry: Task<Void, Never>?

    /// Delay between the end of the last sound and the switch-off of the icon (2 s); changed in tests.
    var silenceDelay: TimeInterval {
        get { state.silenceDelay }
        set { state.silenceDelay = newValue }
    }

    func receive(_ report: PageAudioReport) {
        state.apply(report, at: .now)
        publish()
    }

    /// All of the page's sound has just been paused, or the page changed (navigation, sleep, process termination, web
    /// view released): the icon switches off right away. If the page plays a sound again, its script says so again.
    func reset() {
        state.reset()
        publish()
    }

    /// Copies the state and schedules the switch-off of the icon. Writing the same value notifies no one (Observation
    /// compares `Equatable` values, review CO8).
    private func publish() {
        isPlaying = state.isPlaying
        expiry?.cancel()
        expiry = nil
        guard let deadline = state.silenceDeadline else {
            return
        }
        let delay = max(0, deadline.timeIntervalSinceNow)
        expiry = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else {
                return
            }
            // Same deadline (otherwise this task would have been cancelled): the clock never misses it by a hair.
            state.expire(at: max(.now, deadline))
            publish()
        }
    }
}
