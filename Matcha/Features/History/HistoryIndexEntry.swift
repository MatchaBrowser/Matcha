import Foundation

/// Adresse de l'historique d'un profil, toutes visites de même clé regroupées.
nonisolated struct HistoryIndexEntry: Equatable, Sendable {
    let urlKey: String
    /// Adresse de la visite la plus récente.
    let url: URL
    /// Titre de la visite la plus récente qui en a un.
    let title: String?
    let visitCount: Int
    let lastVisit: Date
    /// Titre et adresse repliés, comparés au texte de la barre de commande et à la recherche de la fenêtre.
    let fields: CommandMatchFields
    let characters: HistoryCharacterMask

    /// `previous` : l'entrée remplacée, dont les champs repliés sont repris si l'adresse et le titre n'ont pas changé.
    init(urlKey: String, url: URL, title: String?, visitCount: Int, lastVisit: Date, previous: Self? = nil) {
        self.urlKey = urlKey
        self.url = url
        self.title = title
        self.visitCount = visitCount
        self.lastVisit = lastVisit
        if let previous, previous.url == url, previous.title == title {
            fields = previous.fields
            characters = previous.characters
        } else {
            // Le titre que la barre de commande affiche et compare (`HistoryProvider`) : l'adresse lisible à défaut.
            fields = CommandMatchFields(titles: [title ?? CommandText.displayURL(url)], url: url)
            characters = HistoryCharacterMask(fields.titles + [fields.address].compactMap(\.self))
        }
    }

    /// Ce que la barre de commande reçoit.
    var historyEntry: HistoryEntry {
        HistoryEntry(url: url, title: title, visitCount: visitCount, lastVisit: lastVisit)
    }
}
