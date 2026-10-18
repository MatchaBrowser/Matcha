import Foundation

/// Message du script de son (`PageAudioScript`, tâche 5.10) pour un document de la page : le cadre principal ou une
/// iframe. Corps attendu : `{frame: String, audible: Bool, gone: Bool?}` ; tout autre corps est ignoré.
nonisolated struct PageAudioReport: Equatable, Sendable {
    /// Longueur maximale de l'identifiant d'un document (le script en tire un court, au hasard).
    static let maximumFrameLength = 64

    /// Identifiant du document, tiré au hasard par le script à son chargement.
    let frame: String
    /// Un élément audio ou vidéo du document joue avec du son (ni coupé, ni à volume nul).
    let isAudible: Bool
    /// Le document s'en va (`pagehide`) : son son s'arrête avec lui.
    let isGone: Bool

    init(frame: String, isAudible: Bool, isGone: Bool = false) {
        self.frame = frame
        self.isAudible = isAudible
        self.isGone = isGone
    }

    /// Lit le corps d'un `WKScriptMessage` ; nil s'il est mal formé.
    init?(messageBody body: Any) {
        guard let fields = body as? [String: Any],
              let frame = fields["frame"] as? String,
              !frame.isEmpty, frame.count <= Self.maximumFrameLength,
              let isAudible = fields["audible"] as? Bool
        else {
            return nil
        }
        let gone = fields["gone"]
        guard gone == nil || gone is Bool else {
            return nil
        }
        self.init(frame: frame, isAudible: isAudible, isGone: gone as? Bool ?? false)
    }
}
