import Foundation
import Observation
import OSLog
import SwiftData

/// Notes of a session (task 12.1): their summaries and the library's folders in memory, observed by the interface, and
/// their `NoteRecord` and `NoteFolderRecord` records. A document is read only when asked for. A private window has no
/// context: it has no notes, and none can be made there.
@MainActor
@Observable
final class NoteStore {
    /// Largest document saved, in UTF-8 bytes (TR2); sync takes smaller ones only (`SYNC.md` § 2.10).
    nonisolated static let maximumContentBytes = 1024 * 1024
    /// Longest title kept, in characters.
    nonisolated static let maximumTitleLength = 300

    /// All the notes of the session, the most recently changed first.
    private(set) var notes: [NoteSummary] = []
    /// All the folders of the library, in no particular order (`folders(ofProfile:parentID:)` sorts them).
    private(set) var folders: [NoteFolder] = []
    /// Store of the notes; nil for a private window.
    @ObservationIgnored let context: ModelContext?

    init(context: ModelContext?) {
        self.context = context
        reload()
    }

    /// True if notes can be made and are saved (false for a private window).
    var isPersistent: Bool {
        context != nil
    }

    /// Reads the summaries and the folders again from the store (after a change made elsewhere, such as sync).
    func reload() {
        guard let context else {
            return
        }
        do {
            var descriptor = FetchDescriptor<NoteRecord>(sortBy: [SortDescriptor(\.modifiedAt, order: .reverse)])
            // The documents stay in the store until asked for.
            descriptor.propertiesToFetch = [
                \.id, \.title, \.profileID, \.createdAt, \.modifiedAt, \.linkURL, \.linkKey, \.linkScopeValue, \.linkTitle, \.contentSize,
            ]
            descriptor.relationshipKeyPathsForPrefetching = [\.folder]
            notes = try context.fetch(descriptor).map(Self.summary)
            folders = try context.fetch(FetchDescriptor<NoteFolderRecord>()).map(Self.folder)
        } catch {
            Logger.notes.error("Notes unreadable: \(error.logSummary, privacy: .public)")
        }
    }

    func notes(ofProfile profileID: UUID?) -> [NoteSummary] {
        notes.filter { $0.profileID == profileID }
    }

    /// Note of the page at `url` for the profile: the most recent one linked to this page, otherwise the most recent one
    /// linked to its site; nil if there is none.
    func note(linkedTo url: URL, profileID: UUID?) -> NoteSummary? {
        let linked = notes.filter { $0.profileID == profileID && $0.link != nil }
        for scope in NoteLinkScope.allCases {
            let key = NoteLink.key(for: url, scope: scope)
            if let note = linked.first(where: { key != nil && $0.link?.scope == scope && $0.link?.key == key }) {
                return note
            }
        }
        return nil
    }

    /// Document of the note; nil if it doesn't exist.
    func content(of id: UUID) -> String? {
        record(id)?.content
    }

    /// Makes a note; nil in a private window, or if the folder doesn't belong to the profile.
    @discardableResult
    func createNote(
        profileID: UUID?,
        title: String = "",
        folderID: UUID? = nil,
        link: NoteLink? = nil,
        date: Date = .now,
    ) -> NoteSummary? {
        guard let context else {
            return nil
        }
        let folder = folderID.flatMap(folderRecord)
        guard folderID == nil || folder?.profileID == profileID else {
            return nil
        }
        let record = NoteRecord(title: Self.cleanTitle(title), profileID: profileID, link: link, date: date)
        record.folder = folder
        context.insert(record)
        save(context)
        let summary = Self.summary(record)
        notes.insert(summary, at: 0)
        Logger.notes.info("Note created (\(link == nil ? "standalone" : "linked", privacy: .public))")
        return summary
    }

    /// Saves the document written by the editor, and its text for search.
    @discardableResult
    func setContent(_ content: String, of id: UUID, date: Date = .now) -> NoteSaveResult {
        guard content.utf8.count <= Self.maximumContentBytes else {
            Logger.notes.notice("Note too large to be saved: \(content.utf8.count, privacy: .public) bytes")
            return .tooLarge
        }
        guard let context, let record = record(id) else {
            return .notFound
        }
        guard record.content != content else {
            return .unchanged
        }
        record.content = content
        record.contentSize = content.utf8.count
        record.plainText = NotePlainText.text(of: content) ?? ""
        touch(record, date: date, in: context)
        return .saved
    }

    /// Gives the note a title (trimmed, `maximumTitleLength` characters at most; empty: the default one).
    func rename(_ id: UUID, to title: String, date: Date = .now) {
        guard let context, let record = record(id) else {
            return
        }
        let title = Self.cleanTitle(title)
        guard record.title != title else {
            return
        }
        record.title = title
        touch(record, date: date, in: context)
    }

    /// Links the note to a page, or detaches it (nil): it then shows in its folder.
    func setLink(_ link: NoteLink?, of id: UUID, date: Date = .now) {
        guard let context, let record = record(id), record.link != link else {
            return
        }
        record.link = link
        touch(record, date: date, in: context)
    }

    /// Puts the note in a folder of its profile, or at the root of the library (nil).
    func move(_ id: UUID, toFolder folderID: UUID?) {
        guard let context, let record = record(id) else {
            return
        }
        let folder = folderID.flatMap(folderRecord)
        guard folderID == nil || folder?.profileID == record.profileID, record.folder?.id != folderID else {
            return
        }
        record.folder = folder
        save(context)
        update(record)
    }

    func delete(_ id: UUID) {
        guard let context, let record = record(id) else {
            return
        }
        context.delete(record)
        save(context)
        notes.removeAll { $0.id == id }
    }

    /// Deletes the notes and folders of a deleted profile.
    func removeAll(profileID: UUID) {
        guard let context else {
            return
        }
        do {
            try context.fetch(FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.profileID == profileID }))
                .forEach(context.delete)
            try context.fetch(FetchDescriptor<NoteFolderRecord>(predicate: #Predicate { $0.profileID == profileID }))
                .forEach(context.delete)
        } catch {
            Logger.notes.error("Notes of the profile not deleted: \(error.logSummary, privacy: .public)")
        }
        save(context)
        notes.removeAll { $0.profileID == profileID }
        folders.removeAll { $0.profileID == profileID }
    }

    // MARK: Records

    func record(_ id: UUID) -> NoteRecord? {
        guard let context else {
            return nil
        }
        var descriptor = FetchDescriptor<NoteRecord>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    func save(_ context: ModelContext) {
        do {
            try context.save()
        } catch {
            Logger.notes.error("Notes not saved: \(error.logSummary, privacy: .public)")
        }
    }

    /// The note changed: new date, saved, back at the top of the list.
    private func touch(_ record: NoteRecord, date: Date, in context: ModelContext) {
        record.modifiedAt = max(date, record.modifiedAt)
        save(context)
        notes.removeAll { $0.id == record.id }
        notes.insert(Self.summary(record), at: 0)
    }

    /// The folder's new state, in place or added.
    func remember(_ record: NoteFolderRecord) {
        let folder = Self.folder(record)
        if let index = folders.firstIndex(where: { $0.id == record.id }) {
            folders[index] = folder
        } else {
            folders.append(folder)
        }
    }

    /// The note's summary, in its place.
    private func update(_ record: NoteRecord) {
        if let index = notes.firstIndex(where: { $0.id == record.id }) {
            notes[index] = Self.summary(record)
        }
    }

    private static func cleanTitle(_ title: String) -> String {
        String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumTitleLength))
    }

    static func summary(_ record: NoteRecord) -> NoteSummary {
        NoteSummary(
            id: record.id,
            title: record.title,
            profileID: record.profileID,
            folderID: record.folder?.id,
            link: record.link,
            createdAt: record.createdAt,
            modifiedAt: record.modifiedAt,
            contentSize: record.contentSize,
        )
    }

    static func folder(_ record: NoteFolderRecord) -> NoteFolder {
        NoteFolder(id: record.id, name: record.name, order: record.order, profileID: record.profileID, parentID: record.parent?.id)
    }
}
