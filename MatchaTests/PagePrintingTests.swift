import AppKit
import Foundation
@testable import Matcha
import PDFKit
import Synchronization
import Testing
import WebKit

/// Printing and PDF export of a real page (task 5.4): print operation set up (title, view frame), printing to a PDF
/// file that is not blank, single-page PDF of the whole page, file name and writing.
@MainActor
struct PagePrintingTests {
    /// Local page `name` whose body is `body`, in an 800 × 600 pt web view that is never shown.
    private func page(_ name: String, body: String) async throws -> BrowserTab {
        let tab = BrowserTab(configuration: TestPages.configuration())
        tab.loadedWebView.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
        tab.load(TestPages.url(name, body: body))
        try await waitUntil { tab.title == name && !tab.isLoading }
        return tab
    }

    private func temporaryFile(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
    }

    @Test func `the print operation is titled after the page and its view has a frame`() async throws {
        let tab = try await page("Facture", body: "<p>Bonjour</p>")
        let operation = PagePrinter.operation(for: tab.loadedWebView, title: tab.displayTitle, printInfo: NSPrintInfo())
        #expect(operation.jobTitle == "Facture")
        #expect(operation.showsPrintPanel)
        #expect(operation.printPanel.options.contains(.showsPreview))
        #expect(operation.view?.frame.isEmpty == false)

        // Web view without a size (never shown): the print view gets one anyway.
        tab.loadedWebView.frame = .zero
        let fallback = PagePrinter.operation(for: tab.loadedWebView, title: "x", printInfo: NSPrintInfo())
        #expect(fallback.view?.frame.size == PagePrinter.fallbackViewSize)
    }

    /// Prints `tab` to a PDF file as the app does: as a sheet on a window (never shown), without a print panel. An
    /// operation started by `run()` never ends with WebKit (endless pages, observed).
    private func printToPDF(_ tab: BrowserTab) async throws -> PDFDocument {
        let window = NSWindow(contentRect: tab.loadedWebView.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = tab.loadedWebView
        let destination = temporaryFile("impression.pdf")
        defer {
            try? FileManager.default.removeItem(at: destination)
            window.contentView = nil
        }
        let info = NSPrintInfo()
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL.rawValue] = destination
        let operation = PagePrinter.operation(for: tab.loadedWebView, title: tab.displayTitle, printInfo: info)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        let completion = PrintCompletion()
        operation.runModal(
            for: window,
            delegate: completion,
            didRun: #selector(PrintCompletion.printOperationDidRun(_:success:contextInfo:)),
            contextInfo: nil,
        )
        try await waitUntil(timeout: .seconds(30)) { completion.success != nil }
        #expect(completion.success == true)
        return try #require(PDFDocument(url: destination))
    }

    @Test func `printing to a PDF file gives pages with the text of the page`() async throws {
        let tab = try await page("impression", body: "<h1>Matcha imprime</h1><p>Bonjour depuis la page</p>")
        let document = try await printToPDF(tab)
        #expect(document.pageCount >= 1)
        #expect(document.string?.contains("Matcha imprime") == true)
    }

    @Test func `the exported PDF holds the whole page in one piece`() async throws {
        let tab = try await page("longue", body: "<p>Haut de page</p><div style='height:3000px'></div><p>Bas de page</p>")
        let data = try await tab.loadedWebView.pdf()
        let destination = temporaryFile("longue.pdf")
        defer { try? FileManager.default.removeItem(at: destination) }
        try PDFExportFile.write(data, to: destination)

        let document = try #require(PDFDocument(url: destination))
        #expect(document.pageCount == 1)
        let page = try #require(document.page(at: 0))
        #expect(page.bounds(for: .mediaBox).height > 3000)
        #expect(document.string?.contains("Haut de page") == true)
        #expect(document.string?.contains("Bas de page") == true)
    }

    @Test(arguments: [
        ("Rapport annuel", "Rapport annuel.pdf"),
        ("AC/DC : Live", "AC-DC - Live.pdf"),
        ("C:\\temp", "C--temp.pdf"),
        ("notice.PDF", "notice.pdf"),
        ("  .Caché.  ", "Caché.pdf"),
        ("Swift 6.4", "Swift 6.4.pdf"),
        ("Ligne\nsuivante", "Lignesuivante.pdf"),
    ])
    func `PDF file name comes from the title`(title: String, expected: String) {
        #expect(PDFExportFile.name(title: title, url: URL(string: "https://example.com/a")) == expected)
    }

    @Test func `PDF file name falls back on the host, then the file, then page`() {
        #expect(PDFExportFile.name(title: nil, url: URL(string: "https://www.example.com/a")) == "www.example.com.pdf")
        #expect(PDFExportFile.name(title: "  ", url: URL(string: "file:///tmp/notes.html")) == "notes.html.pdf")
        #expect(PDFExportFile.name(title: "...", url: URL(string: "about:blank")) == "page.pdf")
        #expect(PDFExportFile.name(title: nil, url: nil) == "page.pdf")
        let long = PDFExportFile.name(title: String(repeating: "é", count: 300), url: nil)
        #expect(long.utf8.count <= 255)
        #expect(long.hasSuffix(".pdf"))
    }

    @Test func `writing replaces an existing file`() throws {
        let destination = temporaryFile("export.pdf")
        defer { try? FileManager.default.removeItem(at: destination) }
        try PDFExportFile.write(Data("premier".utf8), to: destination)
        #expect(try Data(contentsOf: destination) == Data("premier".utf8))
        try PDFExportFile.write(Data("second".utf8), to: destination)
        #expect(try Data(contentsOf: destination) == Data("second".utf8))
    }
}

/// Receives the end of a print job started by `runModal(for:delegate:didRun:contextInfo:)`, called on the printing
/// thread (AppKit prints separately).
private final nonisolated class PrintCompletion: NSObject, Sendable {
    private let result = Mutex<Bool?>(nil)

    var success: Bool? {
        result.withLock { $0 }
    }

    @objc func printOperationDidRun(_: NSPrintOperation, success: Bool, contextInfo _: UnsafeMutableRawPointer?) {
        result.withLock { $0 = success }
    }
}
