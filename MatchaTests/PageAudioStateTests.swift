import Foundation
@testable import Matcha
import Testing

/// Speaker icon rules (task 5.10): on as soon as a document plays a sound, off 2 s after the last one, and right away
/// after a pause, a navigation, a suspension or a process termination.
struct PageAudioStateTests {
    private func report(_ frame: String = "main", audible: Bool, gone: Bool = false) -> PageAudioReport {
        PageAudioReport(frame: frame, isAudible: audible, isGone: gone)
    }

    @Test func `a playing document lights the icon at once`() {
        var state = PageAudioState()
        state.apply(report(audible: true), at: fixedNow)
        #expect(state.isPlaying)
        #expect(state.silenceDeadline == nil)
    }

    @Test func `a silent document never lights the icon`() {
        var state = PageAudioState()
        state.apply(report(audible: false), at: fixedNow)
        state.apply(report(audible: false, gone: true), at: fixedNow)
        #expect(!state.isPlaying)
        #expect(state.silenceDeadline == nil)
    }

    @Test func `the icon goes out two seconds after the last sound`() {
        var state = PageAudioState()
        state.apply(report(audible: true), at: fixedNow)
        state.apply(report(audible: false), at: fixedNow.addingTimeInterval(10))
        #expect(state.isPlaying)
        #expect(state.silenceDeadline == fixedNow.addingTimeInterval(12))

        state.expire(at: fixedNow.addingTimeInterval(11.9))
        #expect(state.isPlaying)
        state.expire(at: fixedNow.addingTimeInterval(12))
        #expect(!state.isPlaying)
        #expect(state.silenceDeadline == nil)
    }

    @Test func `sound coming back before the delay keeps the icon without a blink`() {
        var state = PageAudioState()
        state.apply(report(audible: true), at: fixedNow)
        // End of a track, then the next one.
        state.apply(report(audible: false), at: fixedNow.addingTimeInterval(1))
        state.apply(report(audible: true), at: fixedNow.addingTimeInterval(2.5))
        state.expire(at: fixedNow.addingTimeInterval(3.5))
        #expect(state.isPlaying)
        #expect(state.silenceDeadline == nil)
    }

    @Test func `repeated silent reports do not push the deadline back`() {
        var state = PageAudioState()
        state.apply(report(audible: true), at: fixedNow)
        state.apply(report(audible: false), at: fixedNow.addingTimeInterval(1))
        state.apply(report(audible: false), at: fixedNow.addingTimeInterval(2))
        #expect(state.silenceDeadline == fixedNow.addingTimeInterval(3))
    }

    @Test func `the icon stays while any frame plays`() {
        var state = PageAudioState()
        state.apply(report("main", audible: true), at: fixedNow)
        state.apply(report("frame", audible: true), at: fixedNow)
        state.apply(report("main", audible: false), at: fixedNow.addingTimeInterval(1))
        state.expire(at: fixedNow.addingTimeInterval(10))
        #expect(state.isPlaying)
        #expect(state.audibleFrames == ["frame"])

        // The iframe goes away (`pagehide`): its sound stops with it.
        state.apply(report("frame", audible: true, gone: true), at: fixedNow.addingTimeInterval(20))
        #expect(state.audibleFrames.isEmpty)
        #expect(state.silenceDeadline == fixedNow.addingTimeInterval(22))
    }

    /// Pause from the icon, navigation, suspension, process termination: `reset`.
    @Test func `a reset puts the icon out at once`() {
        var state = PageAudioState()
        state.apply(report("main", audible: true), at: fixedNow)
        state.apply(report("frame", audible: true), at: fixedNow)
        state.reset()
        #expect(!state.isPlaying)
        #expect(state.audibleFrames.isEmpty)
        #expect(state.silenceDeadline == nil)

        // During the delay too; the chosen delay is kept.
        state.silenceDelay = 5
        state.apply(report(audible: true), at: fixedNow)
        state.apply(report(audible: false), at: fixedNow.addingTimeInterval(1))
        #expect(state.silenceDeadline == fixedNow.addingTimeInterval(6))
        state.reset()
        #expect(!state.isPlaying)
        #expect(state.silenceDeadline == nil)
        #expect(state.silenceDelay == 5)
    }

    @Test func `a document that plays again after a reset lights the icon`() {
        var state = PageAudioState()
        state.apply(report(audible: true), at: fixedNow)
        state.reset()
        // The script repeats every 2 s that it is playing: the page has resumed playback.
        state.apply(report(audible: true), at: fixedNow.addingTimeInterval(2))
        #expect(state.isPlaying)
    }
}
