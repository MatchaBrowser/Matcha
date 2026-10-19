import Foundation
@testable import Matcha
import Testing
import WebKit

/// What Matcha tells sites and how it plays media (audit H5).
struct SafariVersionTests {
    private func system(_ major: Int, _ minor: Int) -> OperatingSystemVersion {
        OperatingSystemVersion(majorVersion: major, minorVersion: minor, patchVersion: 0)
    }

    @Test func `the installed safari version is announced`() {
        #expect(SafariVersion.announced(installed: "26.6.2", system: system(26, 6)) == "26.6.2")
        #expect(SafariVersion.announced(installed: "27.0", system: system(26, 6)) == "27.0")
    }

    @Test func `without a readable safari, the version follows macOS`() {
        for broken in [nil, "", "26.x", "26..1", "1.2.3.4", "２６"] {
            #expect(SafariVersion.announced(installed: broken, system: system(27, 1)) == "27.1", "\(broken ?? "nil")")
        }
        #expect(SafariVersion.announced(installed: nil, system: system(15, 4)) == "18.4")
    }

    @MainActor
    @Test func `the user agent names this safari, and sound waits for a click`() {
        let configuration = WebConfigurationFactory().makeConfiguration(websiteDataStore: .nonPersistent())
        #expect(configuration.applicationNameForUserAgent == "Version/\(WebConfigurationFactory.safariVersion) Safari/605.1.15")
        #expect(WebConfigurationFactory.safariVersion == SafariVersion.installed() || SafariVersion.installed() == nil)
        #expect(configuration.mediaTypesRequiringUserActionForPlayback == .audio)
    }
}

/// First size of a browser window (audit H5).
struct BrowserWindowSizeTests {
    @Test func `the first window takes most of the screen, within bounds`() {
        #expect(BrowserWindowSize.defaultSize(visible: CGSize(width: 1512, height: 944)) == CGSize(width: 1285, height: 802))
        #expect(BrowserWindowSize.defaultSize(visible: CGSize(width: 3000, height: 2000)) == BrowserWindowSize.maximum)
        #expect(BrowserWindowSize.defaultSize(visible: CGSize(width: 600, height: 400)) == BrowserWindowSize.minimum)
    }
}
