import OSLog
import WebKit

/// Sound script (task 5.10), injected at the start of each document (main frame and iframes, even from other sites) in
/// an isolated world (`WKContentWorld`): the page does not see it, can neither call nor fool it, and only it can write
/// to `PageAudioMessageHandler`. It listens on `window`, in the capture phase, before any listener of the page (which
/// can't stop the events before it, review WB9), to the events of the document's audio and video elements (`play`,
/// `playing`, `pause`, `ended`, `emptied`, `volumechange`) and tells the app, 100 ms after a burst, whether one of them
/// plays with sound (neither muted nor at zero volume); as long as that is the case, it says so again every 2 s (an
/// element removed from the page stops with no visible event; the app, which clears the state on pause, realigns).
/// Nothing else runs when nothing plays. Does not see: Web Audio, an element outside the document (`new Audio()`), an
/// element in a shadow DOM (its events do not leave it) — `DECISIONS.md`.
@MainActor
enum PageAudioScript {
    static let world = WKContentWorld.world(name: "MatchaPageAudio")
    static let handlerName = "matchaPageAudio"

    /// Hooks the script and its recipient onto `controller` (once per configuration: WebKit refuses a second
    /// recipient with the same name).
    static func install(in controller: WKUserContentController) {
        controller.add(PageAudioMessageHandler(), contentWorld: world, name: handlerName)
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world))
    }

    static let source = """
    (() => {
        const handler = window.webkit?.messageHandlers?.\(handlerName);
        if (!handler) {
            return;
        }
        const frame = Math.random().toString(36).slice(2, 12) + Date.now().toString(36);
        const elements = new Set();
        let audible = false;
        let gone = false;
        let scheduled = false;
        let heartbeat = 0;
        const isAudible = (element) => !element.paused && !element.ended && !element.muted && element.volume > 0;
        const update = () => {
            scheduled = false;
            if (gone) {
                return;
            }
            let now = false;
            for (const element of elements) {
                if (isAudible(element)) {
                    now = true;
                } else if (!element.isConnected) {
                    elements.delete(element);
                }
            }
            if (now || now !== audible) {
                handler.postMessage({ frame, audible: now });
            }
            audible = now;
            if (audible && !heartbeat) {
                heartbeat = setInterval(update, 2000);
            } else if (!audible && heartbeat) {
                clearInterval(heartbeat);
                heartbeat = 0;
            }
        };
        const schedule = () => {
            if (!scheduled) {
                scheduled = true;
                setTimeout(update, 100);
            }
        };
        for (const type of ['play', 'playing', 'pause', 'ended', 'emptied', 'volumechange']) {
            window.addEventListener(type, (event) => {
                if (event.target instanceof HTMLMediaElement) {
                    elements.add(event.target);
                    schedule();
                }
            }, true);
        }
        window.addEventListener('pagehide', () => {
            gone = true;
            audible = false;
            if (heartbeat) {
                clearInterval(heartbeat);
                heartbeat = 0;
            }
            handler.postMessage({ frame, audible: false, gone: true });
        }, true);
        window.addEventListener('pageshow', (event) => {
            if (event.persisted) {
                gone = false;
                schedule();
            }
        }, true);
    })();
    """
}

/// Receives the messages of the sound script and gives them to the sound of the page that sends them
/// (`BrowserWebView.audio`). A malformed message, or one from a web view already released by its tab, is ignored.
final class PageAudioMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let report = PageAudioReport(messageBody: message.body) else {
            Logger.browser.notice("Malformed sound script message: ignored")
            return
        }
        (message.webView as? BrowserWebView)?.audio?.receive(report)
    }
}
