import AppKit
import OSLog
import WebKit

/// « Imprimer… » (⌘P, tâche 5.4) : la page au premier plan, par la zone d'impression de macOS en feuille sur sa
/// fenêtre (aperçu, imprimante, « PDF » pour l'enregistrer en pages). Le titre du travail est celui de la page.
@MainActor
enum PagePrinter {
    /// Taille donnée à la vue d'impression quand la vue web n'en a pas (jamais affichée).
    static let fallbackViewSize = CGSize(width: 800, height: 600)

    /// Opération d'impression de `webView`, intitulée `title`. Sa vue reçoit un cadre : celle que donne WebKit n'en a
    /// pas, et l'impression ne produit alors que des pages blanches (problème connu de `printOperation(with:)`).
    static func operation(for webView: WKWebView, title: String, printInfo: NSPrintInfo = .shared) -> NSPrintOperation {
        let operation = webView.printOperation(with: printInfo)
        operation.jobTitle = title
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.printPanel.options.formUnion([.showsPaperSize, .showsOrientation, .showsScaling, .showsPreview])
        let bounds = webView.bounds
        operation.view?.frame = bounds.isEmpty ? CGRect(origin: .zero, size: fallbackViewSize) : bounds
        return operation
    }

    /// Ouvre la zone d'impression sur la fenêtre de `page` ; rien si la page n'a pas de vue web affichée ou si une
    /// autre feuille est déjà ouverte sur la fenêtre.
    static func print(_ page: BrowserTab) {
        guard let webView = page.webView, let window = webView.window, window.attachedSheet == nil else {
            NSSound.beep()
            return
        }
        operation(for: webView, title: page.displayTitle).runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        Logger.browser.info("Impression de la page")
    }
}
