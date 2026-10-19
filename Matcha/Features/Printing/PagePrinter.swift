import AppKit
import OSLog
import WebKit

/// “Print…” (⌘P, task 5.4): the frontmost page, through the macOS print panel as a sheet on its window (preview,
/// printer, “PDF” to save it as pages). The job title is the page's.
@MainActor
enum PagePrinter {
    /// Size given to the print view when the web view has none (never displayed).
    static let fallbackViewSize = CGSize(width: 800, height: 600)

    /// Print operation of `webView`, titled `title`. Its view is given a frame: the one WebKit provides has none, and
    /// printing then produces only blank pages (known issue of `printOperation(with:)`).
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

    /// Opens the print panel on the window of `page`; nothing if the page has no displayed web view or if another
    /// sheet is already open on the window.
    static func print(_ page: BrowserTab) {
        guard let webView = page.webView, let window = webView.window, window.attachedSheet == nil else {
            NSSound.beep()
            return
        }
        operation(for: webView, title: page.displayTitle).runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
        Logger.browser.info("Impression de la page")
    }
}
