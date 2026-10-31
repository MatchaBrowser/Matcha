import Foundation

/// Today tabs of the account's other Macs (`SYNC.md` § 2.4), opened here in a new tab, labeled with the Mac's name.
/// Nothing without sync or in a private window. The text is ignored: the ranking does the matching.
@MainActor
final class OtherMacsTabsProvider: CommandProvider {
    private let otherMacs: OtherMacsTabs?

    init(otherMacs: OtherMacsTabs?) {
        self.otherMacs = otherMacs
    }

    var answersAtOnce: Bool {
        true
    }

    func candidates(for _: CommandQuery, context: CommandContext) async -> [CommandCandidate] {
        guard let otherMacs, !context.isPrivate else {
            return []
        }
        return otherMacs.macs.flatMap { mac in
            mac.spaces.flatMap(\.tabs).map { tab in
                let title = tab.title.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                return CommandCandidate(
                    kind: .otherMacTab(deviceID: mac.id, deviceName: mac.name, modifiedAt: mac.modifiedAt),
                    title: title ?? CommandText.displayURL(tab.url),
                    url: tab.url,
                )
            }
        }
    }
}
