import Foundation

/// Where links clicked in other apps open (task 8.2).
nonisolated enum ExternalLinkDestination: String, CaseIterable, Identifiable, Sendable {
    /// One mini window per link, like Little Arc: you read, then keep the page (⌘O) or close it.
    case miniWindow
    /// A new tab in the Space shown by the main window.
    case space

    var id: Self {
        self
    }

    var title: LocalizedStringResource {
        switch self {
        case .miniWindow: "A Mini Window"
        case .space: "A New Tab in the Current Space"
        }
    }

    /// Value of the setting in `defaults`, or its default value.
    static func current(in defaults: UserDefaults = .standard) -> ExternalLinkDestination {
        defaults.string(forKey: BrowserSettings.Key.externalLinkDestination).flatMap(Self.init(rawValue:))
            ?? BrowserSettings.externalLinkDestination
    }
}
