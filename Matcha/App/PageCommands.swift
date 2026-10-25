import SwiftUI

/// Commands of the front page (`FrontPage`, task 5.4): File > “Save As…” (⌘S, audit H1), “Export as PDF…” and “Print…”
/// (⌘P), in place of the standard print commands (absent until now: nothing is duplicated); View > “Actual Size” (⌘0),
/// “Zoom In” (⌘+, and ⌘= through `BrowserWebView`), “Zoom Out” (⌘-), after “Reload Page”. The zoom is remembered for
/// the page's site, shown next to its address pill (`ZoomBadge`) and announced to VoiceOver. A page that keeps these
/// shortcuts for itself comes first, as in Safari: WebKit sends it the shortcuts first.
struct PageCommands: Commands {
    let miniWindows: MiniWindowManager
    @FocusedValue(\.tabManager) private var tabManager
    /// Shortcuts chosen in Settings > Shortcuts.
    let shortcuts: MenuShortcutStore

    /// Active mini window, followed by the menu.
    private var miniWindow: MiniWindowController? {
        miniWindows.observedKeyWindow
    }

    private var page: BrowserTab? {
        FrontPage.page(miniWindowTab: miniWindow?.tab, tabManager: tabManager)
    }

    /// Per-site zoom of the active window's pages: the main session's for a mini window.
    private var siteZooms: SiteZoomStore? {
        miniWindow == nil ? tabManager?.siteZooms : miniWindows.siteZooms
    }

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            let page = page
            Button(MenuShortcut.saveAs.title) { self.page.map(PageSaver.start(for:)) }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .saveAs))
                .disabled(page == nil)
            // No shortcut by default, as in Safari; ⇧⌘P is used by some pages (command palette).
            Button("Export as PDF…") { self.page.map(PDFExport.start(for:)) }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .exportPDF))
                .disabled(page == nil)
            Button("Print…") { self.page.map(PagePrinter.print) }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .print))
                .disabled(page == nil)
        }

        CommandGroup(after: .toolbar) {
            let page = page
            Divider()
            Button("Actual Size") { zoom(.actualSize) }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .actualSize))
                .disabled(page.map { !PageZoom.canApply(.actualSize, to: $0) } ?? true)
            Button("Zoom In") { zoom(.zoomIn) }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .zoomIn))
                .disabled(page.map { !PageZoom.canApply(.zoomIn, to: $0) } ?? true)
            Button("Zoom Out") { zoom(.zoomOut) }
                .keyboardShortcut(shortcuts.keyboardShortcut(for: .zoomOut))
                .disabled(page.map { !PageZoom.canApply(.zoomOut, to: $0) } ?? true)
        }
    }

    /// Zooms the page; its badge follows on its own, VoiceOver announces the new zoom.
    private func zoom(_ change: ZoomLevels.Change) {
        guard let page, let level = PageZoom.apply(change, to: page, siteZooms: siteZooms) else {
            return
        }
        ZoomAnnouncement.post(level)
    }
}
