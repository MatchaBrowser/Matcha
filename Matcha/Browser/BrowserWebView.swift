import WebKit

/// Web view of Matcha's tabs.
///
/// What depends on the platform (keyboard, context menu, items dragged from the sidebar, pinch to zoom) is in
/// `AppKit/BrowserWebView+AppKit` and the page menu's files next to it.
final class BrowserWebView: WKWebView {
    /// Recipient of the sidebar items dropped on this page; nil: refused. `SidebarItemDropTarget` is declared by each
    /// platform, with its own drag events.
    weak var sidebarDropTarget: (any SidebarItemDropTarget)?
    /// Context menu choice waiting for the window WebKit opens for it, read by `NavigationCoordinator`.
    var pageMenuIntent = PendingPageMenuIntent()
    /// Sound of the tab this web view belongs to (task 5.10), recipient of the messages of the sound script; nil once
    /// the view is released by its tab.
    weak var audio: PageAudio?
    /// Translation of the page of this web view while it is translated (task 9.2), recipient of the messages of the
    /// translation script; set and cleared by the translation itself.
    weak var translation: PageTranslation?
    /// Translation sessions of the window showing this view (task 9.3), for “Translate to …” of the page menu; set
    /// by that window.
    weak var translationHost: (any PageTranslationHosting)?
    /// Notes panel of the window, for “Add to Note” in the menu of a selection (task 12.6); nil: not offered.
    weak var noteQuotes: (any NoteQuoteReceiving)?
    /// Recipient of the messages of the notification script: the tab's navigation delegate (review CO1).
    weak var notifications: (any PageNotificationReceiving)?

    /// Inspectable according to the developer tools setting, followed as long as the view exists.
    override init(frame: CGRect, configuration: WKWebViewConfiguration) {
        super.init(frame: frame, configuration: configuration)
        WebInspection.apply(to: self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(webInspectionDidChange),
            name: WebInspection.didChange,
            object: nil,
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func webInspectionDidChange() {
        WebInspection.apply(to: self)
    }
}
