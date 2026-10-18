import AppKit
import OSLog

/// Navigateur par défaut de ce Mac (tâche 8.3). macOS demande confirmation avant le changement.
@MainActor
enum DefaultBrowser {
    /// Vrai si Matcha ouvre les liens web de ce Mac.
    static var isMatcha: Bool {
        guard let page = URL(string: "https://example.com"), let app = NSWorkspace.shared.urlForApplication(toOpen: page) else {
            return false
        }
        return Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier
    }

    /// Fait de Matcha le navigateur par défaut, pour `http` puis `https` ; vrai s'il l'est ensuite (l'utilisateur peut
    /// refuser dans la demande de macOS).
    @discardableResult
    static func makeMatcha() async -> Bool {
        for scheme in ["http", "https"] {
            do {
                try await NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpenURLsWithScheme: scheme)
            } catch {
                Logger.app
                    .notice(
                        "Navigateur par défaut inchangé (\(scheme, privacy: .public)) : \(error.localizedDescription, privacy: .public)",
                    )
                return isMatcha
            }
        }
        return isMatcha
    }
}
