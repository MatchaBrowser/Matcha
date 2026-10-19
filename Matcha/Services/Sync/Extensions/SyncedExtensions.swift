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

/// What extension sync remembers on this Mac (task 7.4), in a JSON file (in memory without a file): packages sent or
/// received, extensions from the other Macs awaiting the user's consent, those the user ignored, packages to delete
/// from the server.
@MainActor
@Observable
final class SyncedExtensions {
    private struct Saved: Codable {
        var packages: [String: SyncedPackage] = [:]
        var offers: [String: SyncExtensionFields] = [:]
        var ignored: Set<String> = []
        var obsoleteBlobs: [UUID] = []
        var names: [String: String] = [:]
    }

    /// Package of each extension installed from a file.
    var packages: [String: SyncedPackage] = [:] {
        didSet { save() }
    }

    /// Extensions from the other Macs, not installed here (or whose update needs the user's consent).
    var offers: [String: SyncExtensionFields] = [:] {
        didSet { save() }
    }

    /// Ignored on this Mac: no longer offered.
    var ignored: Set<String> = [] {
        didSet { save() }
    }

    /// Packages to delete from the server.
    var obsoleteBlobs: [UUID] = [] {
        didSet { save() }
    }

    /// Last known name of each extension (before WebKit has read it at launch).
    var names: [String: String] = [:] {
        didSet { save() }
    }

    @ObservationIgnored private let url: URL?
    @ObservationIgnored private var isLoading = false

    init(url: URL?) {
        self.url = url
        guard let url, let data = try? Data(contentsOf: url), let saved = try? SyncCoding.decoder().decode(Saved.self, from: data) else {
            return
        }
        isLoading = true
        packages = saved.packages
        offers = saved.offers
        ignored = saved.ignored
        obsoleteBlobs = saved.obsoleteBlobs
        names = saved.names
        isLoading = false
    }

    /// Offers to show, sorted by name.
    var sortedOffers: [SyncExtensionFields] {
        offers.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func save() {
        guard !isLoading, let url else {
            return
        }
        let saved = Saved(packages: packages, offers: offers, ignored: ignored, obsoleteBlobs: obsoleteBlobs, names: names)
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try SyncCoding.encoder().encode(saved).write(to: url, options: .atomic)
        } catch {
            Logger.sync.error("Synced extensions not saved: \(error.logSummary, privacy: .public)")
        }
    }
}
