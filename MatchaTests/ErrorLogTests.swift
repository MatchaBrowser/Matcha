import Foundation
@testable import Matcha
import Testing

/// Errors in the logs (audit W10): domain and code, never a path or a name.
struct ErrorLogTests {
    @Test func `an error is logged without its description`() {
        let error = CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: "/Users/moi/Documents/secret.json"])
        #expect(error.logSummary == "NSCocoaErrorDomain 260")
        #expect(URLError(.notConnectedToInternet).logSummary == "NSURLErrorDomain -1009")
    }
}
