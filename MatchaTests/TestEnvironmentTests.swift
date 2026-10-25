import Foundation
@testable import Matcha
import Testing

/// The UI tests' launch arguments (audit R6): never the default store, read in Debug builds only.
struct TestEnvironmentTests {
    private let testDefaults = TestDefaults("TestEnvironmentTests")
    @Test func `the default store can never be emptied by a launch argument`() {
        #expect(!TestEnvironment.isResettableStore(named: "default"))
        #expect(!TestEnvironment.isResettableStore(named: ""))
        #expect(TestEnvironment.isResettableStore(named: "PersistenceUITests"))
    }

    @Test func `the unit tests' host is recognized`() {
        #expect(TestEnvironment.isUnitTestHost(["XCTestConfigurationFilePath": "/tmp/x"]))
        #expect(!TestEnvironment.isUnitTestHost([:]))
        #expect(TestEnvironment.usesInMemoryStore(
            defaults: testDefaults.make(),
            environment: ["XCTestConfigurationFilePath": "/tmp/x"],
        ))
    }
}
