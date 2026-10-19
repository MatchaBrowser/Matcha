import CoreServices
import Foundation
@testable import Matcha
import Testing

/// The alert before quitting (audit R7): never when the Mac logs out, restarts or shuts down.
struct QuitConfirmationTests {
    @Test func `the system's quits are never held up`() {
        #expect(QuitConfirmation.asks(isEnabled: true, quitReason: nil))
        #expect(!QuitConfirmation.asks(isEnabled: false, quitReason: nil))
        for reason in [kAELogOut, kAEReallyLogOut, kAERestart, kAEShutDown, kAEShowRestartDialog, kAEShowShutdownDialog] {
            #expect(!QuitConfirmation.asks(isEnabled: true, quitReason: OSType(reason)))
        }
    }
}
