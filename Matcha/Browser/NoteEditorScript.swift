import Foundation
import WebKit

/// Bridge between the app and the notes editor's page (task 12.2, review WB2): a script injected in an isolated world
/// (`world`), the only one where the app's message recipient is reachable. It talks to the page's code (OpenBlock, in the
/// page's world) through DOM events whose detail is JSON text (`events`, the same names in
/// `scripts/note-editor/src/main.tsx`), and checks what it forwards. The app reaches it through `window[bridgeName]`
/// in its world (`callAsyncJavaScript`).
@MainActor
enum NoteEditorScript {
    static let world = WKContentWorld.world(name: "MatchaNoteEditor")
    static let handlerName = "matchaNoteEditor"
    static let bridgeName = "matchaNoteEditor"

    /// Function body, run in `world`: gives the page a note (`payload`: JSON text of `NoteEditorPayload`).
    static let loadBody = "window[bridge]?.load(payload);"
    /// Function body, run in `world`: the document as it is now, if it changed since it was last sent, otherwise null.
    static let flushBody = "return window[bridge]?.flush() ?? null;"

    static func install(in controller: WKUserContentController, handler: any WKScriptMessageHandler) {
        controller.add(handler, contentWorld: world, name: handlerName)
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
    }

    static let source = """
    (() => {
        const handler = window.webkit?.messageHandlers?.\(handlerName);
        if (!handler || window.top !== window || location.protocol !== '\(NoteEditorResources.scheme):') {
            return;
        }
        const parse = (event) => {
            try {
                const detail = JSON.parse(event.detail);
                return detail !== null && typeof detail === 'object' && typeof detail.token === 'string' ? detail : null;
            } catch {
                return null;
            }
        };
        let latest = null;
        document.addEventListener('matcha-note-ready', () => handler.postMessage({ type: 'ready' }));
        document.addEventListener('matcha-note-change', (event) => {
            const detail = parse(event);
            if (detail && typeof detail.content === 'string') {
                latest = { type: 'change', token: detail.token, content: detail.content };
                handler.postMessage(latest);
            }
        });
        document.addEventListener('matcha-note-unreadable', (event) => {
            const detail = parse(event);
            if (detail) {
                handler.postMessage({ type: 'unreadable', token: detail.token });
            }
        });
        window.\(bridgeName) = Object.freeze({
            load(payload) {
                document.dispatchEvent(new CustomEvent('matcha-note-load', { detail: String(payload) }));
            },
            flush() {
                latest = null;
                document.dispatchEvent(new CustomEvent('matcha-note-flush'));
                const change = latest;
                latest = null;
                return change;
            },
        });
    })();
    """
}
