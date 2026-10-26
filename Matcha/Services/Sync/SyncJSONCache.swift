import Foundation

/// JSON of each record's fields, kept as long as its fields stay the same (review SY13): an unchanged record is not
/// encoded again at each detection, which cost most of a cycle with nothing to send. Only in memory; a record that
/// leaves the snapshot leaves the cache. Pure type.
nonisolated struct SyncJSONCache: Sendable {
    private struct Entry: Sendable {
        let fields: SyncFields
        /// nil if the fields can't be encoded (`SyncFields.encodedJSON`).
        let json: SyncJSON?
    }

    private var entries: [UUID: Entry] = [:]

    /// `snapshot`'s fields as JSON, nil for fields that can't be encoded; encoded again only where they changed.
    mutating func encoded(_ snapshot: [UUID: SyncFields]) -> [UUID: SyncJSON?] {
        var result: [UUID: SyncJSON?] = [:]
        var kept: [UUID: Entry] = [:]
        result.reserveCapacity(snapshot.count)
        kept.reserveCapacity(snapshot.count)
        for (id, fields) in snapshot {
            let entry = entries[id].flatMap { $0.fields == fields ? $0 : nil } ?? Entry(fields: fields, json: fields.encodedJSON)
            kept[id] = entry
            result[id] = entry.json
        }
        entries = kept
        return result
    }
}
