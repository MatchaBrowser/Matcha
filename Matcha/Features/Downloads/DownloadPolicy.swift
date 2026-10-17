import Foundation

/// Ce qu'il faut savoir d'une réponse du serveur pour décider si elle s'affiche ou se télécharge.
nonisolated struct DownloadResponse: Equatable, Sendable {
    /// Vrai si WebKit sait afficher ce type de contenu (`WKNavigationResponse.canShowMIMEType`).
    var canShowMIMEType: Bool
    /// En-tête `Content-Disposition`, s'il y en a un.
    var contentDisposition: String?
    /// Code HTTP ; nil hors HTTP (fichier local, `data:`, schéma de l'app).
    var statusCode: Int?
}

extension DownloadResponse {
    /// Réponse telle que WebKit la donne (`WKNavigationResponse.response`) : en-tête et code lus si elle vient d'un
    /// serveur HTTP. Une réponse d'un schéma de l'app (`WKURLSchemeHandler`) arrive sans en-têtes.
    nonisolated init(_ response: URLResponse, canShowMIMEType: Bool) {
        let http = response as? HTTPURLResponse
        self.init(
            canShowMIMEType: canShowMIMEType,
            contentDisposition: http?.value(forHTTPHeaderField: "Content-Disposition"),
            statusCode: http?.statusCode,
        )
    }
}

/// Règles des téléchargements (tâche 5.1), sans dépendance à l'interface.
nonisolated enum DownloadPolicy {
    /// Réponses sans contenu : rien à afficher ni à télécharger, la page reste affichée.
    static let noContentStatusCodes: Set<Int> = [204, 205]

    /// Une réponse se télécharge si WebKit ne sait pas l'afficher, ou si le serveur la donne comme pièce jointe.
    /// Vaut aussi pour un cadre secondaire : c'est ainsi que des sites lancent un téléchargement.
    static func shouldDownload(_ response: DownloadResponse) -> Bool {
        if let status = response.statusCode, noContentStatusCodes.contains(status) {
            return false
        }
        return !response.canShowMIMEType || isAttachment(response.contentDisposition)
    }

    /// Vrai si l'en-tête `Content-Disposition` annonce une pièce jointe : son type, avant le premier `;`, vaut
    /// `attachment` sans tenir compte de la casse ni des espaces ; les paramètres (`filename=…`) sont ignorés.
    /// Comme WebKit (Safari), un autre type (`inline`, type inconnu, en-tête mal formé) laisse la page s'afficher.
    static func isAttachment(_ contentDisposition: String?) -> Bool {
        guard let contentDisposition, let type = contentDisposition.split(separator: ";", omittingEmptySubsequences: false).first
        else {
            return false
        }
        return type.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("attachment") == .orderedSame
    }
}
