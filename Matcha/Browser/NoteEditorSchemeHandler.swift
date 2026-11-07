import Foundation
import OSLog
import WebKit

/// Serves the page of the notes editor and its files (`NoteEditorResources`) to the editor's web view, with its
/// security policy as a header. Any other address fails: nothing else is reachable under `matcha-note:`.
@MainActor
final class NoteEditorSchemeHandler: NSObject, WKURLSchemeHandler {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func webView(_: WKWebView, start urlSchemeTask: any WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url,
              let file = NoteEditorResources.file(for: url),
              let data = NoteEditorResources.data(of: file, in: bundle),
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: 200,
                  httpVersion: "HTTP/1.1",
                  headerFields: NoteEditorResources.headers(for: file),
              )
        else {
            Logger.notes.error("Note editor file not served")
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        urlSchemeTask.didReceive(response)
        urlSchemeTask.didReceive(data)
        urlSchemeTask.didFinish()
    }

    func webView(_: WKWebView, stop _: any WKURLSchemeTask) {}
}
