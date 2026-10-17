import Foundation

/// Adresse courte d'une page : texte de la pastille d'adresse et sous-titre des onglets dans la barre
/// de commande.
nonisolated enum AddressDisplay {
    /// Le domaine sans « www. » (avec le port s'il y en a un), le nom du fichier pour une adresse
    /// `file:`, sinon l'adresse entière (`about:blank`).
    static func short(for url: URL?) -> String {
        guard let url else {
            return ""
        }
        if url.isFileURL {
            return url.lastPathComponent
        }
        guard let host = url.host(), !host.isEmpty else {
            return url.absoluteString
        }
        let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return url.port.map { "\(domain):\($0)" } ?? domain
    }
}
