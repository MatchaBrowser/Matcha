@testable import Matcha
import Testing

/// Permission request rules (task 5.2): remembered decisions, what the banner asks, what it remembers.
struct SitePermissionPolicyTests {
    @Test func `without a saved decision the banner asks`() {
        #expect(SitePermissionPolicy.evaluate([.camera], stored: [:]) == .ask([.camera]))
        #expect(SitePermissionPolicy.evaluate([.camera, .microphone], stored: [:]) == .ask([.camera, .microphone]))
    }

    @Test func `saved decisions answer without asking`() {
        #expect(SitePermissionPolicy.evaluate([.camera], stored: [.camera: .allow]) == .grant)
        #expect(SitePermissionPolicy.evaluate([.camera, .microphone], stored: [.camera: .allow, .microphone: .allow]) == .grant)
        #expect(SitePermissionPolicy.evaluate([.microphone], stored: [.microphone: .deny]) == .deny)
    }

    @Test func `a denied permission wins over an allowed one`() {
        // WebKit grants or denies the request as a whole.
        #expect(SitePermissionPolicy.evaluate([.camera, .microphone], stored: [.camera: .allow, .microphone: .deny]) == .deny)
        #expect(SitePermissionPolicy.evaluate([.camera, .microphone], stored: [.microphone: .deny]) == .deny)
    }

    @Test func `the banner only asks for what has no decision`() {
        #expect(SitePermissionPolicy.evaluate([.camera, .microphone], stored: [.microphone: .allow]) == .ask([.camera]))
        // A decision on another permission does not count.
        #expect(SitePermissionPolicy.evaluate([.camera], stored: [.microphone: .deny]) == .ask([.camera]))
        #expect(SitePermissionPolicy.evaluate([.camera], stored: [.microphone: .allow]) == .ask([.camera]))
    }

    @Test func `an empty request is denied`() {
        #expect(SitePermissionPolicy.evaluate([], stored: [:]) == .deny)
    }

    @Test func `allow once grants and remembers nothing`() {
        #expect(SitePermissionPolicy.grants(.allowOnce))
        #expect(SitePermissionPolicy.decisionsToStore(for: .allowOnce, asked: [.camera, .microphone]).isEmpty)
    }

    @Test func `always allow and don't allow are remembered for what was asked`() {
        #expect(SitePermissionPolicy.grants(.alwaysAllow))
        #expect(!SitePermissionPolicy.grants(.deny))
        #expect(SitePermissionPolicy.decisionsToStore(for: .alwaysAllow, asked: [.camera, .microphone]) == [
            .camera: .allow,
            .microphone: .allow,
        ])
        #expect(SitePermissionPolicy.decisionsToStore(for: .deny, asked: [.microphone]) == [.microphone: .deny])
    }
}
