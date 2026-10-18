import Foundation
import Observation
import OSLog

/// Paquet d'une extension installée depuis un fichier, tel qu'envoyé (ou reçu) par la synchro (`SYNC.md` § 2.5) : sa
/// version, l'identifiant du paquet chiffré, sa clé, son empreinte et sa taille. Type pur.
nonisolated struct SyncedPackage: Codable, Equatable, Sendable {
    var version: String?
    var blobID: UUID
    var blobKey: Data
    var sha256: String
    var size: Int
    var fileName: String

    /// Origine d'une extension pour la synchro.
    var source: SyncExtensionSource {
        .package(blobID: blobID, blobKey: blobKey.base64EncodedString(), sha256: sha256, size: size, fileName: fileName)
    }

    /// Paquet décrit par `source`, s'il est complet.
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

/// Ce que la synchro des extensions retient sur ce Mac (tâche 7.4), dans un fichier JSON (en mémoire sans fichier) :
/// paquets envoyés ou reçus, extensions venues des autres Mac en attente de l'accord de l'utilisateur, celles qu'il a
/// ignorées, paquets à supprimer du serveur.
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

    /// Paquet de chaque extension installée depuis un fichier.
    var packages: [String: SyncedPackage] = [:] {
        didSet { save() }
    }

    /// Extensions des autres Mac, pas installées ici (ou dont la mise à jour demande l'accord de l'utilisateur).
    var offers: [String: SyncExtensionFields] = [:] {
        didSet { save() }
    }

    /// Ignorées sur ce Mac : plus proposées.
    var ignored: Set<String> = [] {
        didSet { save() }
    }

    /// Paquets à supprimer du serveur.
    var obsoleteBlobs: [UUID] = [] {
        didSet { save() }
    }

    /// Dernier nom connu de chaque extension (avant que WebKit l'ait lue au lancement).
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

    /// Offres à montrer, triées par nom.
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
            Logger.sync.error("Extensions synchronisées non enregistrées : \(error.localizedDescription, privacy: .public)")
        }
    }
}
