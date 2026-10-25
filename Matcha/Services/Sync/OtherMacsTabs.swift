import Foundation
import Observation

/// Today tabs of the account's other Macs (`SYNC.md` § 2.4), as sync last received them: shown in the command bar and
/// in History > Tabs from Your Other Macs, never placed in the sidebar. Made once in `AppEnvironment`, filled by
/// `SyncService`, empty while sync is off.
@MainActor
@Observable
final class OtherMacsTabs {
    private(set) var macs: [OtherMac] = []

    /// The other Macs of `state`, read again after each sync cycle.
    func update(from state: SyncState, now: Date = .now) {
        let read = OtherMac.all(in: state, now: now)
        if read != macs {
            macs = read
        }
    }

    func clear() {
        if !macs.isEmpty {
            macs = []
        }
    }
}

/// One of the account's other Macs and its today tabs, by Space. Pure type.
nonisolated struct OtherMac: Identifiable, Equatable, Sendable {
    /// Beyond this age, a Mac's tabs are no longer shown (`SYNC.md` § 2.4).
    static let maximumAge: TimeInterval = 30 * 24 * 60 * 60

    let id: UUID
    let name: String
    /// When that Mac last wrote its tabs.
    let modifiedAt: Date
    let spaces: [SyncDeviceTabsFields.Space]

    /// The other Macs whose tabs `state` holds: not this Mac, not deleted or about to be (a revoked Mac), not older than
    /// `maximumAge`, readable; sorted by name, then by identifier.
    static func all(in state: SyncState, now: Date) -> [OtherMac] {
        var result: [OtherMac] = []
        for (id, entry) in state.entries where entry.type == SyncRecordType.deviceTabs.rawValue && !entry.isIgnored {
            guard let content = entry.remote, !content.deleted, state.pending[id]?.content.deleted != true,
                  now.timeIntervalSince(content.modifiedAt) <= maximumAge,
                  case let .deviceTabs(fields)? = SyncFields(json: content.fields, type: .deviceTabs),
                  fields.deviceId != state.deviceID, !fields.spaces.isEmpty
            else {
                continue
            }
            result.append(OtherMac(id: fields.deviceId, name: fields.name, modifiedAt: content.modifiedAt, spaces: fields.spaces))
        }
        return result.sorted { lhs, rhs in
            let order = lhs.name.localizedStandardCompare(rhs.name)
            return order == .orderedSame ? lhs.id.uuidString < rhs.id.uuidString : order == .orderedAscending
        }
    }
}
