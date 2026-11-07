import SwiftUI
import WebKit

/// The web view of a notes editor (`NoteEditor`) in SwiftUI. The editor keeps its web view: a new view of the same
/// editor shows the same page, without reloading it.
struct NoteEditorView: NSViewRepresentable {
    let editor: NoteEditor

    func makeNSView(context _: Context) -> WKWebView {
        editor.webView
    }

    func updateNSView(_: WKWebView, context _: Context) {}
}
