import AppKit

/// Copie l'adresse d'une page dans le presse-papiers, en URL et en texte.
@MainActor
enum TabLinkCopier {
    static func copy(_ url: URL, to pasteboard: NSPasteboard = .general) {
        copy([url], to: pasteboard)
    }

    /// Plusieurs adresses (lignes de l'historique) : une URL par adresse, et le texte avec une adresse par ligne.
    static func copy(_ urls: [URL], to pasteboard: NSPasteboard = .general) {
        guard !urls.isEmpty else {
            return
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(urls.map { $0 as NSURL })
        pasteboard.setString(urls.map(\.absoluteString).joined(separator: "\n"), forType: .string)
    }
}
