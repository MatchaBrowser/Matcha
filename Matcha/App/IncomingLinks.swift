import Foundation
import OSLog

/// Liens ouverts par d'autres apps (tâche 8.2) : adresses web cliquées dans Mail ou Messages, fichiers HTML ouverts
/// depuis le Finder. Reçus par le délégué de l'app, ils attendent que l'app soit prête (`handler`), au lancement.
@MainActor
final class IncomingLinks {
    static let shared = IncomingLinks()
    /// Schémas acceptés ; les autres sont ignorés.
    static let schemes: Set<String> = ["http", "https", "file"]

    /// Ouvre les liens ; tant qu'il est nil, ils attendent.
    var handler: (([URL]) -> Void)? {
        didSet {
            guard let handler, !waiting.isEmpty else {
                return
            }
            let urls = waiting
            waiting = []
            handler(urls)
        }
    }

    private var waiting: [URL] = []

    func receive(_ urls: [URL]) {
        let accepted = urls.filter { $0.scheme.map { Self.schemes.contains($0.lowercased()) } ?? false }
        guard !accepted.isEmpty else {
            return
        }
        // Jamais l'adresse : le nombre seulement.
        Logger.app.info("Liens d'une autre app : \(accepted.count, privacy: .public)")
        if let handler {
            handler(accepted)
        } else {
            waiting += accepted
        }
    }
}
