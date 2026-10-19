import Foundation

/// An address in a profile's history, with all visits of the same key grouped together.
nonisolated struct HistoryIndexEntry: Equatable, Sendable {
    let urlKey: String
    /// Address of the most recent visit.
    let url: URL
    /// Title of the most recent visit that has one.
    let title: String?
    let visitCount: Int
    let lastVisit: Date
    /// Folded title and address, compared with the command bar's text and the window's search.
    let fields: CommandMatchFields
    let characters: HistoryCharacterMask

    /// `previous`: the replaced entry, whose folded fields are reused if the address and title have not changed.
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
            // The title the command bar shows and compares (`HistoryProvider`): the readable address otherwise.
            fields = CommandMatchFields(titles: [title ?? CommandText.displayURL(url)], url: url)
            characters = HistoryCharacterMask(fields.titles + [fields.address].compactMap(\.self))
        }
    }

    /// What the command bar receives.
    var historyEntry: HistoryEntry {
        HistoryEntry(url: url, title: title, visitCount: visitCount, lastVisit: lastVisit)
    }
}
