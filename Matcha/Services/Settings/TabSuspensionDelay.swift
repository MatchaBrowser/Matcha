import Foundation

/// “Free memory of inactive tabs after” setting (task 5.6): time after which a hidden tab is suspended. Saved
/// value: the number of minutes, 0 for “Never”.
nonisolated enum TabSuspensionDelay: Int, CaseIterable, Identifiable, Sendable {
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60
    case twoHours = 120
    /// No automatic suspension, neither after the delay nor during a memory warning.
    case never = 0

    var id: Self {
        self
    }

    /// Time before suspension; nil for “Never”.
    var duration: Duration? {
        self == .never ? nil : .seconds(rawValue * 60)
    }

    var title: LocalizedStringResource {
        switch self {
        case .fifteenMinutes: LocalizedStringResource("15 minutes", comment: "Option of “Free memory of inactive tabs after”")
        case .thirtyMinutes: LocalizedStringResource("30 minutes", comment: "Option of “Free memory of inactive tabs after”")
        case .oneHour: LocalizedStringResource("1 hour", comment: "Option of “Free memory of inactive tabs after”")
        case .twoHours: LocalizedStringResource("2 hours", comment: "Option of “Free memory of inactive tabs after”")
        case .never: LocalizedStringResource("Never", comment: "Option of “Free memory of inactive tabs after”")
        }
    }
}
