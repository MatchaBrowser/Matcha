import Foundation
@testable import Matcha
import Testing

/// What websites may do without asking (audit W2): per profile, website and action; saved in the app's settings.
@MainActor
struct SiteActionAllowancesTests {
    private let suiteName = "SiteActionAllowancesTests-\(UUID().uuidString)"
    private let zoomSite = SiteOrigin(url: URL(string: "https://zoom.us/")!)!
    private let profile = UUID()

    @Test func `an allowance is kept per profile and comes back after a relaunch`() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let zoom = SiteAction.openApp(scheme: "zoommtg")
        let store = SiteActionAllowances(defaults: defaults)
        store.allow(zoom, origin: zoomSite, profileID: profile)

        #expect(store.isAllowed(zoom, origin: zoomSite, profileID: profile))
        #expect(!store.isAllowed(zoom, origin: zoomSite, profileID: nil))
        #expect(!store.isAllowed(.openApp(scheme: "mailto"), origin: zoomSite, profileID: profile))

        let relaunched = SiteActionAllowances(defaults: defaults)
        #expect(relaunched.isAllowed(zoom, origin: zoomSite, profileID: profile))

        relaunched.removeAll(profileID: profile)
        #expect(SiteActionAllowances(defaults: defaults).entries.isEmpty)
    }

    @Test func `forgetting an allowance makes the website ask again`() throws {
        let store = SiteActionAllowances(defaults: nil)
        store.allow(.openApp(scheme: "zoommtg"), origin: zoomSite, profileID: nil)
        let entry = try #require(store.actions(for: zoomSite, profileID: nil).first)
        store.remove(entry)
        #expect(!store.isAllowed(.openApp(scheme: "zoommtg"), origin: zoomSite, profileID: nil))
    }

    @Test func `unreadable saved entries are ignored`() throws {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set([
            ["profile": "", "site": "https://zoom.us", "action": "open:zoommtg"],
            ["profile": "", "site": "pas une origine", "action": "open:zoommtg"],
            ["profile": "", "site": "https://zoom.us", "action": "inconnue"],
        ], forKey: SiteActionAllowances.defaultsKey)
        #expect(SiteActionAllowances(defaults: defaults).entries.map(\.action) == [.openApp(scheme: "zoommtg")])
    }

    @Test func `deleting a profile forgets what it allowed`() {
        let store = SitePermissionStore(context: nil)
        store.actions.allow(.openApp(scheme: "zoommtg"), origin: zoomSite, profileID: profile)
        store.removeAll(profileID: profile)
        #expect(store.actions.entries.isEmpty)
    }
}
