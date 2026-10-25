import SwiftUI

extension SyncRecoveryKit: Identifiable {
    var id: String {
        recoveryKey
    }
}
