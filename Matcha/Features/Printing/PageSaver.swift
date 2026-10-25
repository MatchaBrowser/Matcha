import AppKit
import OSLog
import UniformTypeIdentifiers
import WebKit

/// “Save As…” in a page's menu: the save panel opens as a sheet on its window, titled after the page, with the choice
/// of format as in Safari: web archive (the page and its resources, `createWebArchiveData`) or source code (reloaded
/// as for “View Page Source”). An error is shown in an alert.
@MainActor
enum PageSaver {
    enum Format: Int, CaseIterable {
        case webArchive
        case pageSource

        var contentType: UTType {
            switch self {
            case .webArchive: .webArchive
            case .pageSource: .html
            }
        }

        var title: String {
            switch self {
            case .webArchive: String(localized: "Web Archive", comment: "Format of File > Save As… for a web page")
            case .pageSource: String(localized: "Page Source", comment: "Format of File > Save As… for a web page")
            }
        }
    }

    static func start(for page: BrowserTab) {
        guard let webView = page.webView, let window = webView.window, window.attachedSheet == nil, let url = page.documentURL else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [Format.webArchive.contentType]
        panel.nameFieldStringValue = PageExportFile.name(title: page.title, url: url, fileExtension: "webarchive")
        let accessory = FormatAccessory(panel: panel)
        panel.accessoryView = accessory.view
        Task {
            guard await panel.beginSheetModal(for: window) == .OK, let destination = panel.url else {
                return
            }
            await save(webView, url: url, format: accessory.format, to: destination, window: window)
        }
    }

    private static func save(_ webView: WKWebView, url: URL, format: Format, to destination: URL, window: NSWindow) async {
        do {
            let data: Data = switch format {
            case .webArchive:
                try await webView.webArchiveData()
            case .pageSource:
                try await PageSourceSchemeHandler.fetch(url, store: webView.configuration.websiteDataStore).0
            }
            try PageExportFile.write(data, to: destination)
            Logger.browser.info("Page saved (\(data.count, privacy: .public) bytes)")
        } catch {
            Logger.browser.error("Page not saved: \(error.logSummary, privacy: .public)")
            showFailure(error, in: window)
        }
    }

    private static func showFailure(_ error: any Error, in window: NSWindow) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = String(localized: "The page couldn't be saved.", comment: "Alert after Save As… failed")
        alert.informativeText = error.localizedDescription
        alert.present(in: window)
    }

    /// Format choice under the save panel; the name's extension follows.
    private final class FormatAccessory: NSObject {
        let view: NSView
        private let popUp = NSPopUpButton()
        private weak var panel: NSSavePanel?

        var format: Format {
            Format(rawValue: popUp.indexOfSelectedItem) ?? .webArchive
        }

        init(panel: NSSavePanel) {
            self.panel = panel
            let label = NSTextField(labelWithString: String(localized: "Format:", comment: "Label of the format menu of Save As…"))
            popUp.addItems(withTitles: Format.allCases.map(\.title))
            // VoiceOver reads “Format” with the menu (review IU21).
            popUp.setAccessibilityTitleUIElement(label)
            let stack = NSStackView(views: [label, popUp])
            stack.edgeInsets = NSEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)
            view = stack
            super.init()
            popUp.target = self
            popUp.action = #selector(formatChanged)
        }

        @objc private func formatChanged() {
            panel?.allowedContentTypes = [format.contentType]
        }
    }
}

private extension WKWebView {
    func webArchiveData() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            createWebArchiveData { continuation.resume(with: $0) }
        }
    }
}
