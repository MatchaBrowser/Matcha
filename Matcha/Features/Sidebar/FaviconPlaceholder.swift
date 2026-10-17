import Foundation

/// Pastille qui remplace l'icône d'un site : initiale du domaine sur une teinte propre au domaine.
nonisolated enum FaviconPlaceholder {
    /// Initiale du domaine, sans « www. », en majuscule ; « ? » sans domaine.
    static func initial(for host: String?) -> String {
        let domain = host.map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? ""
        return domain.first.map { String($0).uppercased() } ?? "?"
    }

    /// Teinte entre 0 et 1, toujours la même pour un domaine donné, d'un lancement à l'autre.
    static func hue(for host: String?) -> Double {
        // djb2 : `hashValue` change à chaque lancement.
        let hash = (host ?? "").utf8.reduce(UInt32(5381)) { ($0 &<< 5) &+ $0 &+ UInt32($1) }
        return Double(hash % 360) / 360
    }
}
