import Foundation
@testable import Matcha
import Testing

/// Depuis quand un onglet est caché (tâche 5.6), modèle pur.
struct TabVisibilityTrackerTests {
    private let first = UUID()
    private let second = UUID()
    private let third = UUID()

    @Test func `a tab leaving the screen is hidden since that moment`() {
        var tracker = TabVisibilityTracker()
        tracker.update(visible: [first], present: [first, second], now: fixedNow)
        #expect(tracker.hiddenSince(first) == nil)
        #expect(tracker.hiddenSince(second) == fixedNow)

        let later = fixedNow.addingTimeInterval(120)
        tracker.update(visible: [second], present: [first, second], now: later)
        #expect(tracker.hiddenSince(first) == later)
        #expect(tracker.hiddenSince(second) == nil)
    }

    @Test func `a hidden tab keeps its date across updates`() {
        var tracker = TabVisibilityTracker()
        tracker.update(visible: [first], present: [first, second], now: fixedNow)
        tracker.update(visible: [first], present: [first, second, third], now: fixedNow.addingTimeInterval(60))
        #expect(tracker.hiddenSince(second) == fixedNow)
        // Vu caché pour la première fois (ouvert en arrière-plan) : depuis cette mise à jour.
        #expect(tracker.hiddenSince(third) == fixedNow.addingTimeInterval(60))
    }

    @Test func `split panes are all visible`() {
        var tracker = TabVisibilityTracker()
        tracker.update(visible: [first, second], present: [first, second, third], now: fixedNow)
        #expect(tracker.hiddenSince(first) == nil)
        #expect(tracker.hiddenSince(second) == nil)
        #expect(tracker.hiddenSince(third) == fixedNow)
    }

    @Test func `closed tabs are forgotten`() {
        var tracker = TabVisibilityTracker()
        tracker.update(visible: [], present: [first, second], now: fixedNow)
        tracker.update(visible: [], present: [first], now: fixedNow.addingTimeInterval(10))
        #expect(tracker.hiddenSince.keys.sorted { $0.uuidString < $1.uuidString } == [first])
        // Rouvert plus tard (même identifiant) : caché depuis son retour.
        tracker.update(visible: [], present: [first, second], now: fixedNow.addingTimeInterval(20))
        #expect(tracker.hiddenSince(second) == fixedNow.addingTimeInterval(20))
    }

    @Test func `no window hides every tab`() {
        var tracker = TabVisibilityTracker()
        tracker.update(visible: [first], present: [first], now: fixedNow)
        tracker.update(visible: [], present: [first], now: fixedNow.addingTimeInterval(5))
        #expect(tracker.hiddenSince(first) == fixedNow.addingTimeInterval(5))
    }
}
