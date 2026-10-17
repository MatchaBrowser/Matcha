import Foundation

/// Progression des téléchargements, sans dépendance à l'interface : part reçue d'un téléchargement, et de tous
/// ceux en cours pour l'anneau du bouton de la barre latérale.
nonisolated enum DownloadProgressSummary {
    /// Part reçue, de 0 à 1 ; nil si la taille est inconnue.
    static func fraction(completed: Int64, total: Int64?) -> Double? {
        guard let total, total > 0 else {
            return nil
        }
        return min(1, max(0, Double(completed) / Double(total)))
    }

    /// Part reçue de l'ensemble des téléchargements en cours, pondérée par leur taille ; nil si l'un d'eux a une
    /// taille inconnue (l'anneau ne peut alors rien promettre) ou s'il n'y en a aucun.
    static func overallFraction(of downloads: [(completed: Int64, total: Int64?)]) -> Double? {
        guard !downloads.isEmpty else {
            return nil
        }
        var completed: Int64 = 0
        var total: Int64 = 0
        for download in downloads {
            guard let size = download.total, size > 0 else {
                return nil
            }
            completed += min(max(0, download.completed), size)
            total += size
        }
        return fraction(completed: completed, total: total)
    }

    /// Taille lisible (« 12 Mo »), dans la langue de l'utilisateur, comme le Finder.
    static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
