import Foundation
@testable import Matcha
import Testing

/// Règles de la mise en veille (tâche 5.6) : quels onglets, dans quel ordre, selon la raison.
struct TabSuspensionPolicyTests {
    private static let thirtyMinutes: TimeInterval = 30 * 60

    /// Onglet chargé et sans activité, caché depuis `minutes` minutes avant `fixedNow` (nil : affiché).
    private func candidate(
        _ id: UUID = UUID(),
        hiddenFor minutes: Double?,
        isLoaded: Bool = true,
        prompt: Bool = false,
        capture: Bool = false,
        audio: Bool = false,
        popup: Bool = false,
    ) -> TabLifecycleCandidate {
        TabLifecycleCandidate(
            id: id,
            hiddenSince: minutes.map { fixedNow.addingTimeInterval(-$0 * 60) },
            isLoaded: isLoaded,
            hasPendingPermissionPrompt: prompt,
            isCapturingMedia: capture,
            isPlayingAudio: audio,
            hasOpenPopupWindow: popup,
        )
    }

    private func pool(
        _ candidates: [TabLifecycleCandidate],
        _ reason: TabSuspensionReason,
        delay: TimeInterval? = thirtyMinutes,
    ) -> [UUID] {
        TabSuspensionPolicy.pool(candidates, reason: reason, delay: delay, now: fixedNow)
    }

    @Test func `only loaded hidden tabs without prompt or capture are eligible`() {
        #expect(TabSuspensionPolicy.isEligible(candidate(hiddenFor: 40)))
        #expect(!TabSuspensionPolicy.isEligible(candidate(hiddenFor: nil)))
        #expect(!TabSuspensionPolicy.isEligible(candidate(hiddenFor: 40, isLoaded: false)))
        #expect(!TabSuspensionPolicy.isEligible(candidate(hiddenFor: 40, prompt: true)))
        #expect(!TabSuspensionPolicy.isEligible(candidate(hiddenFor: 40, capture: true)))
        // Tâche 5.10 : l'icône haut-parleur suffit, sans demander à WebKit.
        #expect(!TabSuspensionPolicy.isEligible(candidate(hiddenFor: 40, audio: true)))
        // Tâche 5.8 : la page d'origine d'une fenêtre de connexion ouverte garde son lien `window.opener`.
        #expect(!TabSuspensionPolicy.isEligible(candidate(hiddenFor: 40, popup: true)))
    }

    @Test func `inactivity takes tabs hidden longer than the delay, oldest first`() {
        let recent = candidate(hiddenFor: 10)
        let old = candidate(hiddenFor: 90)
        let limit = candidate(hiddenFor: 30)
        let older = candidate(hiddenFor: 31)
        let shown = candidate(hiddenFor: nil)
        let result = pool([recent, old, limit, shown, older], .inactivity)
        #expect(result == [old.id, older.id, limit.id])
    }

    @Test func `inactivity skips busy and unloaded tabs`() {
        let candidates = [
            candidate(hiddenFor: 60, isLoaded: false),
            candidate(hiddenFor: 60, prompt: true),
            candidate(hiddenFor: 60, capture: true),
            candidate(hiddenFor: 60, audio: true),
            candidate(hiddenFor: 60, popup: true),
        ]
        #expect(pool(candidates, .inactivity).isEmpty)
    }

    @Test func `never unloads nothing, even under memory pressure`() {
        let candidates = [candidate(hiddenFor: 600), candidate(hiddenFor: 5)]
        for reason in [TabSuspensionReason.inactivity, .memoryWarning, .memoryCritical] {
            #expect(pool(candidates, reason, delay: nil).isEmpty)
        }
    }

    @Test func `memory warning takes the oldest half of tabs hidden for a minute`() {
        let tabs = [10.0, 0.5, 3, 25, 2].map { candidate(hiddenFor: $0) }
        let examined = pool(tabs, .memoryWarning)
        // Ni le délai réglé ni l'onglet quitté il y a 30 s.
        #expect(examined == [tabs[3].id, tabs[0].id, tabs[2].id, tabs[4].id])
        #expect(TabSuspensionPolicy.limit(examined, reason: .memoryWarning) == [tabs[3].id, tabs[0].id])
        // Moitié arrondie au-dessus : un seul onglet part.
        #expect(TabSuspensionPolicy.limit([tabs[3].id], reason: .memoryWarning) == [tabs[3].id])
        #expect(TabSuspensionPolicy.limit([], reason: .memoryWarning).isEmpty)
    }

    @Test func `critical memory takes every hidden tab, oldest first`() {
        let tabs = [0.1, 45, 3].map { candidate(hiddenFor: $0) }
        let examined = pool(tabs + [candidate(hiddenFor: nil)], .memoryCritical)
        #expect(examined == [tabs[1].id, tabs[2].id, tabs[0].id])
        #expect(TabSuspensionPolicy.limit(examined, reason: .memoryCritical) == examined)
        #expect(TabSuspensionPolicy.limit(examined, reason: .inactivity) == examined)
    }

    @Test func `same hidden time keeps a stable order`() throws {
        let first = try candidate(#require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")), hiddenFor: 40)
        let second = try candidate(#require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")), hiddenFor: 40)
        #expect(pool([second, first], .inactivity) == [first.id, second.id])
    }

    @Test func `durations convert to seconds`() {
        #expect(Duration.seconds(90).timeInterval == 90)
        #expect(Duration.milliseconds(1500).timeInterval == 1.5)
    }
}
