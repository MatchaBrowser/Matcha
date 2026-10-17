import Foundation
@testable import Matcha

// Données partagées des tests de la barre de commande.

/// Instant de référence des tests de classement.
let fixedNow = Date(timeIntervalSinceReferenceDate: 800_000_000)

/// Space affiché des tests de classement.
let shownSpaceID = UUID()

func query(_ text: String, engine: SearchEngine = .google) -> CommandQuery {
    CommandQuery(text: text, searchEngine: engine)
}

/// Onglet ouvert : `spaceName` nil pour le Space affiché ; `activity` = dernière activité.
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

/// Adresse de l'historique visitée `visits` fois, la dernière il y a `daysAgo` jours.
func history(_ title: String, url: String, visits: Int = 1, daysAgo: Double = 0) -> CommandCandidate {
    CommandCandidate(
        kind: .history(visitCount: visits, lastVisit: fixedNow.addingTimeInterval(-daysAgo * 86400)),
        title: title,
        url: URL(string: url),
    )
}

/// Action avec ses titre et mots-clés anglais (`defaultValue` du catalogue).
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

/// Générateur pseudo-aléatoire reproductible (SplitMix64).
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
