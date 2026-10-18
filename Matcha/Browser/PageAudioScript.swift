import OSLog
import WebKit

/// Script de son (tâche 5.10), injecté au début de chaque document (cadre principal et iframes, même d'autres sites)
/// dans un monde isolé (`WKContentWorld`) : la page ne le voit pas, ne peut ni l'appeler ni le tromper, et seul lui peut
/// écrire à `PageAudioMessageHandler`. Il écoute, en phase de capture, les événements des éléments audio et vidéo du
/// document (`play`, `playing`, `pause`, `ended`, `emptied`, `volumechange`) et dit à l'app, 100 ms après une rafale,
/// si l'un d'eux joue avec du son (ni coupé ni à volume nul) ; tant que c'est le cas, il le redit toutes les 2 s (un
/// élément retiré de la page s'arrête sans événement visible ; l'app, qui efface l'état à la pause, se recale). Rien
/// d'autre ne tourne quand rien ne joue. Ne voit pas : Web Audio, un élément hors du document (`new Audio()`), un
/// élément dans un shadow DOM (ses événements n'en sortent pas) — `DECISIONS.md`.
@MainActor
enum PageAudioScript {
    static let world = WKContentWorld.world(name: "MatchaPageAudio")
    static let handlerName = "matchaPageAudio"

    /// Branche le script et son destinataire sur `controller` (une fois par configuration : WebKit refuse un second
    /// destinataire du même nom).
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
            document.addEventListener(type, (event) => {
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

/// Reçoit les messages du script de son et les donne au son de la page qui les envoie (`BrowserWebView.audio`). Un
/// message mal formé, ou d'une vue web déjà libérée par son onglet, est ignoré.
final class PageAudioMessageHandler: NSObject, WKScriptMessageHandler {
    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let report = PageAudioReport(messageBody: message.body) else {
            Logger.browser.notice("Message du script de son mal formé : ignoré")
            return
        }
        (message.webView as? BrowserWebView)?.audio?.receive(report)
    }
}
