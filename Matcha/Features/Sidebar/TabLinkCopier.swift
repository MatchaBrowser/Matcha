import AppKit

/// Copie l'adresse d'une page dans le presse-papiers, en URL et en texte.
@MainActor
enum TabLinkCopier {
    static func copy(_ url: URL, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString(url.absoluteString, forType: .string)
    }
}
