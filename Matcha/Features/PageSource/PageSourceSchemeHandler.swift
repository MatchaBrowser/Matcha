import Foundation
import OSLog
import WebKit

/// Serves `matcha-source:` pages (`PageSource`): reloads the page with the cookies of its profile (a signed-in page
/// shows its real code), then shows it as text. A local page is read from disk.
///
/// Only viewers opened by the app are served: “View Page Source” and the restoration of a viewer tab authorize their
/// address for the profile's data store (`authorize`). A page can't use the scheme to send requests with the user's
/// cookies or to read files: an address it builds itself only gets an explanation, without network or disk, and the
/// viewer is never served inside another page (frame, image).
@MainActor
final class PageSourceSchemeHandler: NSObject, WKURLSchemeHandler {
    static let shared = PageSourceSchemeHandler()

    /// The viewer's response headers: no script, no request, no sniffing, an origin of its own.
    static let headers = [
        "Content-Type": "text/html; charset=utf-8",
        "Content-Security-Policy": "sandbox; default-src 'none'; style-src 'unsafe-inline'",
        "X-Content-Type-Options": "nosniff",
    ]

    private var loads: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// Viewer addresses opened by the app, by data store.
    private var authorized: [ObjectIdentifier: Set<URL>] = [:]

    /// Allows `viewer` to be loaded in the web views that use `store`.
    func authorize(_ viewer: URL, in store: WKWebsiteDataStore) {
        guard PageSource.pageURL(fromViewer: viewer) != nil else {
            return
        }
        authorized[ObjectIdentifier(store), default: []].insert(viewer)
    }

    func isAuthorized(_ viewer: URL, in store: WKWebsiteDataStore) -> Bool {
        authorized[ObjectIdentifier(store)]?.contains(viewer) == true
    }

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let request = urlSchemeTask.request
        guard let viewer = request.url, let page = PageSource.pageURL(fromViewer: viewer) else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }
        // A viewer is a page of its own: never a frame or a resource of another page.
        guard request.mainDocumentURL == viewer else {
            urlSchemeTask.didFailWithError(URLError(.noPermissionsToReadFile))
            return
        }
        let store = webView.configuration.websiteDataStore
        let title = String(localized: "Source of \(page.absoluteString)", comment: "Title of the tab that shows the source of a page")
        guard isAuthorized(viewer, in: store) else {
            let message = String(
                localized: "To see the source of this page, open the page, then choose View Page Source in its menu.",
                comment: "Page source viewer opened without the page's menu (link, restored history)",
            )
            Self.reply(PageSource.errorHTML(title: title, message: message, detail: ""), for: viewer, to: urlSchemeTask)
            return
        }
        let id = ObjectIdentifier(urlSchemeTask)
        loads[id] = Task { [weak self] in
            let result: Result<(Data, String?), any Error>
            do {
                result = try await .success(Self.fetch(page, store: store))
            } catch {
                Logger.browser.notice("Unreadable page source: \(error.logSummary, privacy: .public)")
                result = .failure(error)
            }
            let html = await PageSourceLoader.viewerHTML(for: result, title: title)
            guard let self, loads.removeValue(forKey: id) != nil, !Task.isCancelled else {
                return
            }
            Self.reply(html, for: viewer, to: urlSchemeTask)
        }
    }

    func webView(_: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        loads.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }

    /// Content of `page` and its encoding, with the cookies of `store`.
    static func fetch(_ page: URL, store: WKWebsiteDataStore) async throws -> (Data, String?) {
        let cookies = page.isFileURL ? [] : await store.httpCookieStore.allCookies()
        let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) "
            + WebConfigurationFactory.applicationNameForUserAgent
        return try await PageSourceLoader.load(page, cookies: cookies, userAgent: userAgent)
    }

    private static func reply(_ html: String, for viewer: URL, to urlSchemeTask: any WKURLSchemeTask) {
        let body = Data(html.utf8)
        let response = HTTPURLResponse(url: viewer, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)
            ?? URLResponse(url: viewer, mimeType: "text/html", expectedContentLength: body.count, textEncodingName: "utf-8")
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(body)
        urlSchemeTask.didFinish()
    }
}
