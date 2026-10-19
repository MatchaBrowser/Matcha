import Foundation

/// What a new tab shows.
nonisolated enum NewTabPage: String, CaseIterable, Identifiable, Sendable {
    /// Empty tab, cursor in the address bar.
    case blank
    /// Homepage from the settings.
    case homePage

    var id: Self {
        self
    }

    var title: LocalizedStringResource {
        switch self {
        case .blank: LocalizedStringResource("Empty Page", comment: "Option of “New tabs open with”")
        case .homePage: LocalizedStringResource("Your Homepage", comment: "Option of “New tabs open with”")
        }
    }
}
