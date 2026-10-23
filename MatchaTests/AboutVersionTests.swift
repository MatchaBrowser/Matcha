@testable import Matcha
import Testing

/// The About panel shows the version of the build.
struct AboutVersionTests {
    private let info: [String: Any] = ["CFBundleShortVersionString": "1.0", "CFBundleVersion": "1"]

    @Test func `a Debug build shows its commit in place of the build number`() {
        let version = AboutVersion(info: info, commit: "3f2a9c1-dirty\n")
        #expect(version.applicationVersion == "1.0")
        #expect(version.build == "3f2a9c1-dirty")
    }

    @Test func `a published build shows its full version and its build number`() {
        let published: [String: Any] = [
            "CFBundleShortVersionString": "1.0.0",
            "CFBundleVersion": "128",
            AboutVersion.releaseVersionKey: "1.0.0-beta.1",
        ]
        let version = AboutVersion(info: published, commit: "")
        #expect(version.applicationVersion == "1.0.0-beta.1")
        #expect(version.build == "128")
    }

    @Test func `without a published version or a commit, the bundle's version`() {
        var unpublished = info
        unpublished[AboutVersion.releaseVersionKey] = ""
        let version = AboutVersion(info: unpublished, commit: nil)
        #expect(version.applicationVersion == "1.0")
        #expect(version.build == "1")
    }
}
