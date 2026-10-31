import WebKit

/// What the context menu of a page asks of the UI delegate of its web view (`NavigationCoordinator`).
@MainActor
protocol PageMenuDelegate: AnyObject {
    /// True if “Open Link in Peek” makes sense in `webView`: a tab of the sidebar (not Peek, where a link already loads
    /// in place, nor a mini window or a sign-in window, which have no Peek).
    func pageMenuOffersPeek(in webView: WKWebView) -> Bool
    /// Back, Forward, Save As…, Print…, Translate (or Show Original), View Page Source, chosen in the page menu of
    /// `webView`.
    func pageMenu(perform command: PageCommand, in webView: WKWebView)
    /// Translation of the page of `webView` (its language, whether it is translated), for “Translate to …”; nil: none.
    func pageMenuTranslation(in webView: WKWebView) -> PageTranslation?
    /// “Translate to Another Language” › `language`, chosen in the page menu of `webView`.
    func pageMenu(translateInto language: Locale.Language, in webView: WKWebView)
}
