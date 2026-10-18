import Foundation

/// Adresse montrée par la barre d'une fenêtre de connexion (tâche 5.8) : on doit voir quel site demande le mot de
/// passe, quel que soit le titre que la page se donne. Le titre de la fenêtre vient de la page, cette barre jamais.
nonisolated struct PopupAddress: Equatable, Sendable {
    enum Security: Equatable, Sendable {
        /// https : connexion chiffrée (cadenas).
        case secure
        /// http : « Non sécurisé ».
        case notSecure
        /// Pas un site (fichier local, `about:`, `data:`) : rien.
        case none
    }

    /// L'hôte (sans « www. », avec le port s'il n'est pas celui par défaut) pour un site ; le nom du fichier pour un
    /// fichier local ; `about:blank` ; sinon le seul schéma (`data:`), jamais le contenu d'une adresse `data:`.
    let text: String
    let security: Security
}

nonisolated extension PopupAddress {
    init(url: URL?) {
        guard let url else {
            text = ""
            security = .none
            return
        }
        if let origin = SiteOrigin.web(of: url) {
            text = origin.displayHost
            security = origin.scheme == "https" ? .secure : .notSecure
            return
        }
        security = .none
        let scheme = url.scheme?.lowercased() ?? ""
        if url.isFileURL {
            text = url.lastPathComponent
        } else if let origin = SiteOrigin(url: url) {
            text = "\(origin.scheme)://\(origin.displayHost)"
        } else if scheme == "about" {
            text = url.absoluteString
        } else {
            text = scheme.isEmpty ? "" : "\(scheme):"
        }
    }
}
