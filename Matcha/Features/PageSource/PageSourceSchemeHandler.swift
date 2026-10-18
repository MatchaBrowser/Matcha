import Foundation
import OSLog
import WebKit

/// Sert les pages `matcha-source:` (`PageSource`) : relit la page avec les cookies de son profil (une page connectée
/// montre son vrai code), puis la montre comme du texte. Une page locale est lue sur le disque.
@MainActor
final class PageSourceSchemeHandler: NSObject, WKURLSchemeHandler {
    static let shared = PageSourceSchemeHandler()

    private var loads: [ObjectIdentifier: Task<Void, Never>] = [:]

    func webView(_ webView: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        let id = ObjectIdentifier(urlSchemeTask)
        guard let viewer = urlSchemeTask.request.url, let page = PageSource.pageURL(fromViewer: viewer) else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }
        let store = webView.configuration.websiteDataStore
        let title = String(localized: "Source of \(page.absoluteString)", comment: "Title of the tab that shows the source of a page")
        loads[id] = Task { [weak self] in
            let html: String
            do {
                let (data, encoding) = try await Self.fetch(page, store: store)
                html = PageSource.viewerHTML(source: PageSource.text(of: data, textEncodingName: encoding), title: title)
            } catch {
                Logger.browser.notice("Code source illisible : \(error.localizedDescription, privacy: .public)")
                let message = String(
                    localized: "The source of this page couldn't be loaded.",
                    comment: "Page source viewer, after an error",
                )
                html = PageSource.errorHTML(title: title, message: message, detail: error.localizedDescription)
            }
            guard let self, loads.removeValue(forKey: id) != nil, !Task.isCancelled else {
                return
            }
            let body = Data(html.utf8)
            urlSchemeTask.didReceive(URLResponse(
                url: viewer,
                mimeType: "text/html",
                expectedContentLength: body.count,
                textEncodingName: "utf-8",
            ))
            urlSchemeTask.didReceive(body)
            urlSchemeTask.didFinish()
        }
    }

    func webView(_: WKWebView, stop urlSchemeTask: any WKURLSchemeTask) {
        loads.removeValue(forKey: ObjectIdentifier(urlSchemeTask))?.cancel()
    }

    /// Contenu de `page` et son encodage : lu sur le disque pour un fichier, sinon demandé au site avec les cookies de
    /// `store` (session éphémère, présentée comme Safari).
    static func fetch(_ page: URL, store: WKWebsiteDataStore) async throws -> (Data, String?) {
        if page.isFileURL {
            return try (Data(contentsOf: page), nil)
        }
        let configuration = URLSessionConfiguration.ephemeral
        if let cookies = configuration.httpCookieStorage {
            cookies.cookieAcceptPolicy = .always
            for cookie in await store.httpCookieStore.allCookies() {
                cookies.setCookie(cookie)
            }
        }
        configuration.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) "
                + WebConfigurationFactory.applicationNameForUserAgent,
        ]
        let session = URLSession(configuration: configuration)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: page)
        return (data, response.textEncodingName)
    }
}
