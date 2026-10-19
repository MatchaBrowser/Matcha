import Foundation
@testable import Matcha
import Testing

/// The UI tests' launch arguments (audit R6): never the default store, read in Debug builds only.
struct TestEnvironmentTests {
    @Test func `the default store can never be emptied by a launch argument`() {
        #expect(!TestEnvironment.isResettableStore(named: "default"))
        #expect(!TestEnvironment.isResettableStore(named: ""))
        #expect(TestEnvironment.isResettableStore(named: "PersistenceUITests"))
    }

    @Test func `the unit tests' host is recognized`() throws {
        #expect(TestEnvironment.isUnitTestHost(["XCTestConfigurationFilePath": "/tmp/x"]))
        #expect(!TestEnvironment.isUnitTestHost([:]))
        #expect(try TestEnvironment.usesInMemoryStore(
            defaults: #require(UserDefaults(suiteName: "TestEnvironmentTests-\(UUID().uuidString)")),
            environment: ["XCTestConfigurationFilePath": "/tmp/x"],
        ))
    }
}
