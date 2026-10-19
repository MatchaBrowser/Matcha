import Foundation
@testable import Matcha

// Shared data for the command bar tests.

/// Reference instant for the ranking tests.
let fixedNow = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// Displayed Space for the ranking tests.
let shownSpaceID = UUID()

func query(_ text: String, engine: SearchEngine = .google) -> CommandQuery {
    CommandQuery(text: text, searchEngine: engine)
}

/// Open tab: `spaceName` nil for the displayed Space; `activity` = last activity.
func tab(
    _ title: String,
    url: String,
    place: TabPlace = .today,
    spaceName: String? = nil,
    activity: Date = fixedNow,
    id: UUID = UUID(),
) -> CommandCandidate {
    let reference = TabReference(tabID: id, spaceID: spaceName == nil ? shownSpaceID : UUID())
    return CommandCandidate(
        kind: .tab(reference, place: place, spaceName: spaceName, lastActivity: activity),
        title: title,
        url: URL(string: url),
    )
}

/// History address visited `visits` times, the last time `daysAgo` days ago.
func history(_ title: String, url: String, visits: Int = 1, daysAgo: Double = 0) -> CommandCandidate {
    CommandCandidate(
        kind: .history(visitCount: visits, lastVisit: fixedNow.addingTimeInterval(-daysAgo * 86400)),
        title: title,
        url: URL(string: url),
    )
}

/// Action with its English title and keywords (`defaultValue` from the catalog).
func action(_ id: CommandActionID) -> CommandCandidate {
    let texts: (title: String, keywords: String) = switch id {
    case .newSpace: ("New Space", "new create add space")
    case .copyURL: ("Copy URL", "copy link address url")
    case .settings: ("Settings", "settings preferences options")
    }
    let keywords = texts.keywords.split(separator: " ").map(String.init)
    return CommandCandidate(kind: .action(id, keywords: keywords), title: texts.title, url: nil)
}

func suggestion(_ text: String) -> CommandCandidate {
    CommandCandidate(kind: .suggestion, title: text, url: nil)
}

/// Reproducible pseudo-random generator (SplitMix64).
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
