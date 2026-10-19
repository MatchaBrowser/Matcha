import Foundation
import Observation
import OSLog

/// Package of an extension installed from a file, as sent (or received) by sync (`SYNC.md` § 2.5): its version, the
/// identifier of the encrypted package, its key, its digest and its size. Pure type.
nonisolated struct SyncedPackage: Codable, Equatable, Sendable {
    var version: String?
    var blobID: UUID
    var blobKey: Data
    var sha256: String
    var size: Int
    var fileName: String

    /// Origin of an extension for sync.
    var source: SyncExtensionSource {
        .package(blobID: blobID, blobKey: blobKey.base64EncodedString(), sha256: sha256, size: size, fileName: fileName)
    }

    /// Package described by `source`, if it is complete.
    init?(source: SyncExtensionSource, version: String?) {
        guard source.kind == .package, let blobID = source.blobId, let key = source.blobKey.flatMap({ Data(base64Encoded: $0) }),
              key.count == 32, let sha256 = source.sha256, let size = source.size
        else {
            return nil
        }
        self.init(version: version, blobID: blobID, blobKey: key, sha256: sha256, size: size, fileName: source.fileName ?? "extension.zip")
    }

    init(version: String?, blobID: UUID, blobKey: Data, sha256: String, size: Int, fileName: String) {
        self.version = version
        self.blobID = blobID
        self.blobKey = blobKey
        self.sha256 = sha256
        self.size = size
        self.fileName = fileName
    }
}
