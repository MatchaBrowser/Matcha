import AppKit
import OSLog
import UniformTypeIdentifiers
import WebKit

/// « Exporter en PDF… » (tâche 5.4) : toute la page au premier plan, d'un seul tenant (`createPDF`, sans découpage en
/// feuilles : pour des pages, « Imprimer… » puis « PDF »). La zone d'enregistrement s'ouvre en feuille sur la fenêtre
/// de la page, avec le titre de la page pour nom ; le PDF n'est créé qu'une fois l'emplacement choisi. Une erreur est
/// montrée dans une alerte.
@MainActor
enum PDFExport {
    static func start(for page: BrowserTab) {
        guard let webView = page.webView, let window = webView.window, window.attachedSheet == nil else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = PDFExportFile.name(title: page.title, url: page.url)
        Task {
            guard await panel.beginSheetModal(for: window) == .OK, let destination = panel.url else {
                return
            }
            await export(webView, to: destination, window: window)
        }
    }

    private static func export(_ webView: WKWebView, to destination: URL, window: NSWindow) async {
        do {
            let data = try await webView.pdf()
            try PDFExportFile.write(data, to: destination)
            Logger.browser.info("Page exportée en PDF (\(data.count, privacy: .public) octets)")
        } catch {
            Logger.browser.error("Export en PDF impossible : \(error.localizedDescription, privacy: .private)")
            showFailure(error, in: window)
        }
    }

    private static func showFailure(_ error: any Error, in window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "The page couldn't be exported as PDF.", comment: "Alert after File > Export as PDF… failed")
        alert.informativeText = error.localizedDescription
        if window.isVisible, window.attachedSheet == nil {
            alert.beginSheetModal(for: window)
        } else {
            alert.runModal()
        }
    }
}
