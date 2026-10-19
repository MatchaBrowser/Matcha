import Foundation

/// Texts of the periods of “Clear History…”.
extension HistoryPeriod {
    var title: LocalizedStringResource {
        switch self {
        case .lastHour: LocalizedStringResource("The Last Hour", comment: "Clear History: period")
        // Key distinct from the list's “Today” header.
        case .today: LocalizedStringResource("Clear History Today", defaultValue: "Today", comment: "Clear History: period since midnight")
        case .todayAndYesterday: LocalizedStringResource("Today and Yesterday", comment: "Clear History: period")
        case .allHistory: LocalizedStringResource("All History", comment: "Clear History: period")
        }
    }
}
