import Foundation

extension SyncService {
    /// Name of this Mac shown in the list of devices.
    nonisolated static var deviceName: String {
        Host.current().localizedName ?? "Mac"
    }
}
