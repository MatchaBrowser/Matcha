import Foundation

/// Textes des périodes de « Effacer l'historique… ».
extension HistoryPeriod {
    var title: LocalizedStringResource {
        switch self {
        case .lastHour: LocalizedStringResource("The Last Hour", comment: "Clear History: period")
        // Clé distincte de l'en-tête « Today » de la liste.
        case .today: LocalizedStringResource("Clear History Today", defaultValue: "Today", comment: "Clear History: period since midnight")
        case .todayAndYesterday: LocalizedStringResource("Today and Yesterday", comment: "Clear History: period")
        case .allHistory: LocalizedStringResource("All History", comment: "Clear History: period")
        }
    }
}
