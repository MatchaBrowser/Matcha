import Foundation
import OSLog

/// Changes to the vault, made only while it is open (`VAULT.md` § 5.1, § 9): each one becomes an edit, sealed at once,
/// then written in an atomic batch.
extension VaultService {
    /// At most 10 000 items and tombstones (`VAULT.md` § 4.1).
    static let maximumItems = 10000
    /// The trash empties itself after 30 days (`VAULT.md` § 9.6).
    static let trashLifetime: TimeInterval = 30 * 24 * 3600

    /// The current content of an item, opened: this Mac's edit, or the version in force.
    func content(of id: UUID) throws -> VaultItemContent {
        try opened(id).content
    }

    private func opened(_ id: UUID) throws -> VaultItemCodec.Opened {
        guard let session else {
            throw VaultError.locked
        }
        guard let sealed = state.edits[id].map(\.sealed) ?? state.items[id]?.sealed else {
            throw VaultError.unavailable
        }
        noteActivity()
        return try session.codec.open(sealed, id: id)
    }

    /// Saves an item: a new one without `id`. Its secrets that change go into its history (`VAULT.md` § 9.5); it is
    /// dated after the version it replaces. Returns its identifier.
    @discardableResult
    func save(_ content: VaultItemContent, id: UUID? = nil) throws -> UUID {
        let id = try stage(content, id: id)
        didEdit()
        return id
    }

    /// Saves several items in one write (an import, `VAULT.md` § 10): beyond 100, a large write (§ 5.1).
    func saveAll(_ contents: [VaultItemContent]) throws -> Int {
        var saved = 0
        defer {
            if saved > 0 {
                didEdit()
            }
        }
        for content in contents {
            try stage(content, id: nil)
            saved += 1
        }
        return saved
    }

    /// The edit of a save, without writing it yet.
    @discardableResult
    private func stage(_ content: VaultItemContent, id: UUID?) throws -> UUID {
        guard let session, let account else {
            throw VaultError.locked
        }
        let id = id ?? UUID()
        let previous = try? opened(id)
        if previous == nil, state.items.count + state.edits.count >= Self.maximumItems {
            throw VaultError.vaultFull
        }
        if let previous, !previous.content.isEditable, content.overview.trashedAt == previous.content.overview.trashedAt {
            throw VaultError.readOnly
        }
        var next = content
        if let previous {
            next.keepHistory(of: previous.content)
            let kept = Set(next.details.files.map(\.id))
            noteObsoleteFiles(removed: previous.content.details.files.filter { !kept.contains($0.id) })
        } else {
            next.details.createdAt = next.details.createdAt ?? now()
        }
        next.overview.modifiedAt = later(than: [previous?.content.overview.modifiedAt])
        next.overview.modifiedBy = account.deviceID
        let sealed = try session.codec.seal(next, id: id, itemKey: previous?.itemKey)
        state.edits[id] = VaultEdit(
            sealed: sealed,
            base: state.edits[id]?.base ?? state.items[id]?.sealed,
            modifiedAt: next.overview.modifiedAt,
            modifiedBy: next.overview.modifiedBy,
            trashedAt: next.overview.trashedAt,
            blobs: state.edits[id]?.blobs ?? [],
        )
        return id
    }

    /// Puts items in the trash, or takes them out of it.
    func setTrashed(_ ids: [UUID], _ trashed: Bool) throws {
        for id in ids {
            var item = try content(of: id)
            guard item.overview.isTrashed != trashed else {
                continue
            }
            item.overview.trashedAt = trashed ? now() : nil
            try save(item, id: id)
        }
    }

    /// Deletes for good items that are in the trash; the others are left as they are (`VAULT.md` § 5.6).
    func deleteForever(_ ids: [UUID]) throws {
        guard session != nil else {
            throw VaultError.locked
        }
        for id in ids {
            guard let item = try? content(of: id), item.overview.isTrashed else {
                continue
            }
            noteObsoleteFiles(removed: item.details.files)
            if state.items[id] == nil, state.edits[id]?.base == nil {
                // Never written: nothing to delete on the server.
                state.edits[id] = nil
            } else {
                state.edits[id] = VaultEdit(sealed: nil, base: state.edits[id]?.base ?? state.items[id]?.sealed)
            }
        }
        didEdit()
    }

    func emptyTrash() throws {
        try deleteForever(items.filter(\.overview.isTrashed).map(\.id))
    }

    /// Items in the trash for more than 30 days, deleted for good by the first open Mac that sees them.
    func purgeTrash() {
        let old = items.filter { item in
            item.overview.trashedAt.map { now().timeIntervalSince($0) > Self.trashLifetime } ?? false
        }
        guard !old.isEmpty, clockLead() < Self.maximumClockLead else {
            return
        }
        try? deleteForever(old.map(\.id))
    }

    /// After an edit: saved, listed, and written.
    private func didEdit() {
        noteActivity()
        saveState()
        rebuildItems()
        guard let session, let account else {
            return
        }
        // Nothing read yet: written on an empty view; a vault already on the server makes it a conflict, read and merged.
        let view = serverState.map {
            VaultServerView.read(from: $0, vaultID: session.keys.vaultID, identifiers: account.identifiers)
        } ?? VaultServerView()
        let previous = writeTask
        writeTask = Task { [weak self] in
            await previous?.value
            guard let self, !isWriting else {
                return
            }
            isWriting = true
            await write(view: view)
            isWriting = false
            account.requestCycle()
        }
    }
}
