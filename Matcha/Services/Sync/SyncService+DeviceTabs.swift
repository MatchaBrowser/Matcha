import Foundation

/// Today tabs between the Macs of the account (`SYNC.md` § 2.4): each Mac publishes its own, the others only show them.
extension SyncService {
    /// The other Macs' tabs, read again from the sync state.
    func refreshOtherMacs() {
        if let engine = coordinator?.engine {
            otherMacs?.update(from: engine.state)
        } else {
            otherMacs?.clear()
        }
    }

    /// Signing out: a last cycle sends the deletion of this Mac's tabs, if the server answers.
    func withdrawDeviceTabs() async {
        guard let coordinator, let store else {
            return
        }
        store.publishesDeviceTabs = false
        _ = try? await coordinator.engine.sync()
    }

    /// The Mac `deviceID` was revoked: its tabs are deleted for all the Macs.
    func forgetDeviceTabs(of deviceID: UUID) {
        guard let coordinator else {
            return
        }
        let engine = coordinator.engine
        engine.queueDeletion(of: engine.identifiers.deviceTabs(deviceID), type: .deviceTabs)
        refreshOtherMacs()
        coordinator.syncSoon(after: .seconds(1))
    }
}
