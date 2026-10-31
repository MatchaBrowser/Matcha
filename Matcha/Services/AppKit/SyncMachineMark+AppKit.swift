import CryptoKit
import Foundation
import IOKit

/// This machine's mark (`SYNC.md` § 5): SHA-256 of its `IOPlatformUUID` (IOKit, public API). A copy of the Mac
/// (Migration Assistant, Time Machine restore) has the same device identifier and tokens as the original, on another
/// machine: it then draws a new identifier and signs in again, so that the two never reuse the same refresh token.
nonisolated enum SyncMachineMark {
    static func current() -> String? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPlatformExpertDevice"))
        guard service != 0 else {
            return nil
        }
        defer { IOObjectRelease(service) }
        let property = IORegistryEntryCreateCFProperty(service, kIOPlatformUUIDKey as CFString, kCFAllocatorDefault, 0)
        guard let uuid = property?.takeRetainedValue() as? String else {
            return nil
        }
        return SHA256.hash(data: Data(uuid.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
