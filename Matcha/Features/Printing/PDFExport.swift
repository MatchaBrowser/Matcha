import AppKit
import OSLog
import UniformTypeIdentifiers
import WebKit

/// “Export as PDF…” (task 5.4): the whole frontmost page, in one piece (`createPDF`, without splitting into sheets:
/// for pages, “Print…” then “PDF”). The save panel opens as a sheet on the page's window, with the page's title as
/// name; the PDF is created only once the location is chosen. An error is shown in an alert.
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
        panel.nameFieldStringValue = PDFExportFile.name(title: page.title, url: page.documentURL)
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
            Logger.browser.info("Page exported as PDF (\(data.count, privacy: .public) bytes)")
        } catch {
            Logger.browser.error("PDF export failed: \(error.localizedDescription, privacy: .private)")
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
