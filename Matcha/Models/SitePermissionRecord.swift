import Foundation
import SwiftData

/// Décision retenue d'un profil pour un site et une permission (tâche 5.2) : « Toujours autoriser » ou « Refuser »
/// dans le bandeau, ou le choix fait dans les réglages du site. « Autoriser une fois » n'est jamais enregistré, une
/// fenêtre privée non plus (ses décisions restent en mémoire, `SitePermissionStore`). Reste sur le Mac (`SYNC.md`).
@Model
final class SitePermissionRecord {
    var id = UUID()
    /// Profil dont les pages sont concernées.
    var profileID: UUID?
    /// Origine de la page principale (`SiteOrigin.key`) : « https://meet.google.com », « http://localhost:8080 ».
    var originKey = ""
    /// Permission, en texte (`SitePermissionKind`) : `camera`, `microphone`.
    var kindValue = ""
    /// Décision, en texte (`SitePermissionDecision`) : `allow`, `deny`.
    var decisionValue = ""
    var date = Date.now

    init(profileID: UUID?, originKey: String, kind: SitePermissionKind, decision: SitePermissionDecision, date: Date = .now) {
        self.profileID = profileID
        self.originKey = originKey
        kindValue = kind.rawValue
        decisionValue = decision.rawValue
        self.date = date
    }
}
