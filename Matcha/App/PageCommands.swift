import SwiftUI

/// Commandes de la page au premier plan (`FrontPage`, tâche 5.4) : Fichier > « Exporter en PDF… » et « Imprimer… »
/// (⌘P), à la place des commandes d'impression standard (absentes jusqu'ici : rien n'est doublé) ; Présentation >
/// « Taille réelle » (⌘0), « Zoom avant » (⌘+, et ⌘= par `BrowserWebView`), « Zoom arrière » (⌘-), après « Recharger la
/// page ». Le zoom est retenu pour le site de la page, montré à côté de sa pastille d'adresse (`ZoomBadge`) et annoncé
/// à VoiceOver. Une page qui garde ces raccourcis pour elle passe avant, comme dans Safari : WebKit lui envoie les
/// raccourcis d'abord.
struct PageCommands: Commands {
    let miniWindows: MiniWindowManager
    @FocusedValue(\.tabManager) private var tabManager

    /// Mini-fenêtre active : `keyWindowID` est lu pour que le menu suive, la fenêtre est relue à chaque action.
    private var miniWindow: MiniWindowController? {
        _ = miniWindows.keyWindowID
        return miniWindows.keyWindow
    }

    private var page: BrowserTab? {
        FrontPage.page(miniWindowTab: miniWindow?.tab, tabManager: tabManager)
    }

    /// Zoom par site des pages de la fenêtre active : celui de la session principale pour une mini-fenêtre.
    private var siteZooms: SiteZoomStore? {
        miniWindow == nil ? tabManager?.siteZooms : miniWindows.siteZooms
    }

    var body: some Commands {
        CommandGroup(replacing: .printItem) {
            let page = page
            // Sans raccourci, comme dans Safari ; ⇧⌘P sert à certaines pages (palette de commandes).
            Button("Export as PDF…") { self.page.map(PDFExport.start(for:)) }
                .disabled(page == nil)
            Button("Print…") { self.page.map(PagePrinter.print) }
                .keyboardShortcut("p")
                .disabled(page == nil)
        }

        CommandGroup(after: .toolbar) {
            let page = page
            Divider()
            Button("Actual Size") { zoom(.actualSize) }
                .keyboardShortcut("0")
                .disabled(page.map { !PageZoom.canApply(.actualSize, to: $0) } ?? true)
            Button("Zoom In") { zoom(.zoomIn) }
                .keyboardShortcut("+")
                .disabled(page.map { !PageZoom.canApply(.zoomIn, to: $0) } ?? true)
            Button("Zoom Out") { zoom(.zoomOut) }
                .keyboardShortcut("-")
                .disabled(page.map { !PageZoom.canApply(.zoomOut, to: $0) } ?? true)
        }
    }

    /// Zoome la page ; son badge suit de lui-même, VoiceOver annonce le nouveau zoom.
    private func zoom(_ change: ZoomLevels.Change) {
        guard let page, let level = PageZoom.apply(change, to: page, siteZooms: siteZooms) else {
            return
        }
        ZoomAnnouncement.post(level)
    }
}
