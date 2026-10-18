import Foundation
@testable import Matcha
import Testing

/// Règles de l'icône haut-parleur (tâche 5.10) : allumée dès qu'un document joue un son, éteinte 2 s après le dernier,
/// tout de suite après une pause, une navigation, une mise en veille ou un arrêt du processus.
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
        // Fin d'un morceau, puis le suivant.
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

        // L'iframe s'en va (`pagehide`) : son son s'arrête avec elle.
        state.apply(report("frame", audible: true, gone: true), at: fixedNow.addingTimeInterval(20))
        #expect(state.audibleFrames.isEmpty)
        #expect(state.silenceDeadline == fixedNow.addingTimeInterval(22))
    }

    /// Pause par l'icône, navigation, mise en veille, arrêt du processus : `reset`.
    @Test func `a reset puts the icon out at once`() {
        var state = PageAudioState()
        state.apply(report("main", audible: true), at: fixedNow)
        state.apply(report("frame", audible: true), at: fixedNow)
        state.reset()
        #expect(!state.isPlaying)
        #expect(state.audibleFrames.isEmpty)
        #expect(state.silenceDeadline == nil)

        // Pendant le délai aussi ; le délai choisi reste.
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
        // Le script redit qu'il joue toutes les 2 s : la page a relancé la lecture.
        state.apply(report(audible: true), at: fixedNow.addingTimeInterval(2))
        #expect(state.isPlaying)
    }
}
