import Foundation
import OSLog

/// Logging categories, one per module. An error is logged by its domain and code (`logSummary`), never by its
/// description.
nonisolated extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.matchabrowser.matcha"

    /// App, settings.
    static let app = Logger(subsystem: subsystem, category: "App")
    /// Tabs, navigation and WebKit.
    static let browser = Logger(subsystem: subsystem, category: "Browser")
    /// Site icons.
    static let favicons = Logger(subsystem: subsystem, category: "Favicons")
    /// Command bar and search suggestions.
    static let commandBar = Logger(subsystem: subsystem, category: "CommandBar")
    /// Link peek (Shift-click).
    static let peek = Logger(subsystem: subsystem, category: "Peek")
    /// Mini windows and their global shortcut; never an address or typed text.
    static let miniWindow = Logger(subsystem: subsystem, category: "MiniWindow")
    /// Downloads; never a full address or a file name, only the host, private.
    static let downloads = Logger(subsystem: subsystem, category: "Downloads")
    /// Site permissions (camera, microphone, notifications) and site data; never a full address, only the host.
    static let permissions = Logger(subsystem: subsystem, category: "Permissions")
    /// Notifications of the websites; never an address, a title or a text, only the host, private.
    static let notifications = Logger(subsystem: subsystem, category: "Notifications")
    /// Browsing history; never an address or a title, only numbers.
    static let history = Logger(subsystem: subsystem, category: "History")
    /// Tab memory (suspension of hidden tabs); never an address, only numbers.
    static let tabLifecycle = Logger(subsystem: subsystem, category: "TabLifecycle")
    /// Ad and tracker blocker: lists, durations, counts; never an address or a site.
    static let contentBlocker = Logger(subsystem: subsystem, category: "ContentBlocker")
    /// Web extensions: loading, windows and tabs opened for them, permission requests; never an address, and their
    /// identifiers (which give their names) are private.
    static let extensions = Logger(subsystem: subsystem, category: "Extensions")
    /// Import from other browsers: numbers only; never an address, a title or a name.
    static let imports = Logger(subsystem: subsystem, category: "Import")
    /// Sync: numbers and states only; never content, an address or a name.
    static let sync = Logger(subsystem: subsystem, category: "Sync")
    /// Translation of the pages: methods, counts and languages; never a text or an address.
    static let translation = Logger(subsystem: subsystem, category: "Translation")
}
