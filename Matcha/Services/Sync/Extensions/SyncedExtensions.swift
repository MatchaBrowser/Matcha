import Foundation
import Observation
import OSLog

/// What extension sync remembers on this Mac (task 7.4), in a JSON file (in memory without a file): packages sent or
/// received, extensions from the other Macs awaiting the user's consent, those the user ignored, packages to delete
/// from the server. One file per server and account, read when its sync starts (`use(url:)`), deleted when the user
/// signs out (review SY11).
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
        var packageFailures: [String: SyncedPackageFailure] = [:]
        var adopted: Set<String> = []

        init(
            packages: [String: SyncedPackage],
            offers: [String: SyncExtensionFields],
            ignored: Set<String>,
            ignoredUpdates: [String: String],
            obsoleteBlobs: [UUID],
            names: [String: String],
            packageFailures: [String: SyncedPackageFailure],
            adopted: Set<String>,
        ) {
            self.packages = packages
            self.offers = offers
            self.ignored = ignored
            self.ignoredUpdates = ignoredUpdates
            self.obsoleteBlobs = obsoleteBlobs
            self.names = names
            self.packageFailures = packageFailures
            self.adopted = adopted
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            packages = container.lenient([String: SyncedPackage].self, forKey: .packages) ?? [:]
            offers = container.lenient([String: SyncExtensionFields].self, forKey: .offers) ?? [:]
            ignored = container.lenient(Set<String>.self, forKey: .ignored) ?? []
            ignoredUpdates = container.lenient([String: String].self, forKey: .ignoredUpdates) ?? [:]
            obsoleteBlobs = container.lenient([UUID].self, forKey: .obsoleteBlobs) ?? []
            names = container.lenient([String: String].self, forKey: .names) ?? [:]
            packageFailures = container.lenient([String: SyncedPackageFailure].self, forKey: .packageFailures) ?? [:]
            adopted = container.lenient(Set<String>.self, forKey: .adopted) ?? []
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

    /// Packages that couldn't be sent, by extension (review SY16).
    var packageFailures: [String: SyncedPackageFailure] = [:] {
        didSet { save() }
    }

    /// Extensions just installed from an offer: their state here becomes the reference of their record, so their
    /// first sync sends nothing back (review SY1).
    var adopted: Set<String> = [] {
        didSet { save() }
    }

    @ObservationIgnored private var url: URL?
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
        load(url.flatMap(Self.saved(at:)))
    }

    /// The file of the account whose sync starts: read, or empty. `legacy`, the single file of earlier versions, becomes
    /// the file of the first account that starts.
    func use(url newURL: URL?, legacy: URL? = nil) {
        let files = FileManager.default
        if let newURL, let legacy, !files.fileExists(atPath: newURL.path), files.fileExists(atPath: legacy.path) {
            do {
                try files.moveItem(at: legacy, to: newURL)
            } catch {
                Logger.sync.error("Synced extensions not moved: \(error.logSummary, privacy: .public)")
            }
        }
        url = newURL
        load(newURL.flatMap(Self.saved(at:)))
    }

    /// Forgets everything and deletes the file: the user signed out (package keys included).
    func forget() {
        if let url {
            try? FileManager.default.removeItem(at: url)
        }
        url = nil
        load(nil)
    }

    private func load(_ saved: Saved?) {
        isLoading = true
        packages = saved?.packages ?? [:]
        offers = saved?.offers ?? [:]
        ignored = saved?.ignored ?? []
        ignoredUpdates = saved?.ignoredUpdates ?? [:]
        obsoleteBlobs = saved?.obsoleteBlobs ?? []
        names = saved?.names ?? [:]
        packageFailures = saved?.packageFailures ?? [:]
        adopted = saved?.adopted ?? []
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
            packageFailures: packageFailures,
            adopted: adopted,
        )
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try SyncCoding.encoder().encode(saved).write(to: url, options: .atomic)
        } catch {
            Logger.sync.error("Synced extensions not saved: \(error.logSummary, privacy: .public)")
        }
    }
}
