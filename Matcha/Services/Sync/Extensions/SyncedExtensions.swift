import Foundation
import Observation
import OSLog

/// What extension sync remembers on this Mac (task 7.4), in a JSON file (in memory without a file): packages sent or
/// received, extensions from the other Macs awaiting the user's consent, those the user ignored, packages to delete
/// from the server.
@MainActor
@Observable
final class SyncedExtensions {
    /// Saved form, read leniently: a field missing from an older file takes its default value.
    private struct Saved: Codable {
        var packages: [String: SyncedPackage] = [:]
        var offers: [String: SyncExtensionFields] = [:]
        var ignored: Set<String> = []
        var ignoredUpdates: [String: String] = [:]
        var obsoleteBlobs: [UUID] = []
        var names: [String: String] = [:]

        init(
            packages: [String: SyncedPackage],
            offers: [String: SyncExtensionFields],
            ignored: Set<String>,
            ignoredUpdates: [String: String],
            obsoleteBlobs: [UUID],
            names: [String: String],
        ) {
            self.packages = packages
            self.offers = offers
            self.ignored = ignored
            self.ignoredUpdates = ignoredUpdates
            self.obsoleteBlobs = obsoleteBlobs
            self.names = names
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            packages = container.lenient([String: SyncedPackage].self, forKey: .packages) ?? [:]
            offers = container.lenient([String: SyncExtensionFields].self, forKey: .offers) ?? [:]
            ignored = container.lenient(Set<String>.self, forKey: .ignored) ?? []
            ignoredUpdates = container.lenient([String: String].self, forKey: .ignoredUpdates) ?? [:]
            obsoleteBlobs = container.lenient([UUID].self, forKey: .obsoleteBlobs) ?? []
            names = container.lenient([String: String].self, forKey: .names) ?? [:]
        }
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

    /// Updates ignored on this Mac (“Ignore This Version”): digest of the package not to offer again, by extension.
    var ignoredUpdates: [String: String] = [:] {
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

    /// The saved state; nil without a file, or for one that can't be read, which is logged (review TR4).
    private static func saved(at url: URL) -> Saved? {
        do {
            return try SyncCoding.decoder().decode(Saved.self, from: Data(contentsOf: url))
        } catch CocoaError.fileReadNoSuchFile {
            return nil
        } catch {
            Logger.sync.error("Synced extensions unreadable: \(error.logSummary, privacy: .public)")
            return nil
        }
    }

    init(url: URL?) {
        self.url = url
        guard let url, let saved = Self.saved(at: url) else {
            return
        }
        isLoading = true
        packages = saved.packages
        offers = saved.offers
        ignored = saved.ignored
        ignoredUpdates = saved.ignoredUpdates
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
        let saved = Saved(
            packages: packages,
            offers: offers,
            ignored: ignored,
            ignoredUpdates: ignoredUpdates,
            obsoleteBlobs: obsoleteBlobs,
            names: names,
        )
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try SyncCoding.encoder().encode(saved).write(to: url, options: .atomic)
        } catch {
            Logger.sync.error("Synced extensions not saved: \(error.logSummary, privacy: .public)")
        }
    }
}
