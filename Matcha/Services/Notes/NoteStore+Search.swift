import Foundation
import OSLog
import SwiftData

/// Search in the notes (tasks 12.4 and 12.7): titles and texts, whatever the case and the accents.
extension NoteStore {
    /// Notes of the profile whose title or text contains `text`; nil for an empty search (no filter).
    func search(_ text: String, profileID: UUID?) -> Set<UUID>? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            return nil
        }
        guard let context else {
            return []
        }
        var descriptor = FetchDescriptor<NoteRecord>(predicate: #Predicate {
            $0.profileID == profileID && ($0.title.localizedStandardContains(text) || $0.plainText.localizedStandardContains(text))
        })
        descriptor.propertiesToFetch = [\.id]
        do {
            return try Set(context.fetch(descriptor).map(\.id))
        } catch {
            Logger.notes.error("Notes not searched: \(error.logSummary, privacy: .public)")
            return []
        }
    }
}
