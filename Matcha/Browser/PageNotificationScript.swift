import Foundation
import WebKit

/// Matcha's own `Notification` in the pages: WebKit offers no public API to grant notifications (its own answers
/// “denied” to every request while still saying “default”, so websites ask again on every load). Two scripts, injected
/// at the start of each document (review WB2):
/// - in an isolated world (`world`), the script that talks to the app (`PageNotificationMessageHandler`, reachable from
///   this world only) and holds the decisions of the websites this page has shown, the destination's given before each
///   navigation (`stateSource`) and a change in the settings at once (`stateBody`, review WB10). It sends a
///   request only from the main frame, right after a click or a key press (`navigator.userActivation`, read where the
///   page can't redefine it); a cross-origin frame or an insecure page reads “denied”;
/// - in the page's world, a thin layer that the page sees: `Notification`, `navigator.permissions.query({ name:
///   'notifications' })` and `ServiceWorkerRegistration.showNotification` (from the page; a service worker's own
///   notifications stay out of reach). It talks to the isolated script through DOM events with names drawn at each
///   launch, and only learns the permission of its own origin.
/// The page can fool its own layer, never the isolated script nor the checks of the app (`NavigationCoordinator+
/// Notifications`).
@MainActor
enum PageNotificationScript {
    static let world = WKContentWorld.world(name: "MatchaPageNotifications")
    static let handlerName = "matchaNotifications"
    /// Property of `window`, in the isolated world, through which the app reaches the script (states, events).
    static let bridgeName = "matchaNotifications"
    /// DOM events from the page's layer to the isolated script, and back; random for each launch.
    private static let toWorld = "e" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    private static let toPage = "e" + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()

    /// Hooks the scripts and their recipient onto `controller` (once per controller, like the sound script).
    static func install(in controller: WKUserContentController) {
        controller.addScriptMessageHandler(PageNotificationMessageHandler(), contentWorld: world, name: handlerName)
        controller.addUserScript(WKUserScript(source: worldSource, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: world))
        controller.addUserScript(WKUserScript(source: pageSource, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
    }

    /// State script, in the isolated world: notifications available or not (private window) and, with an `origin`
    /// (key of a website), its decision, read by the script injected before it. The page never sees it.
    static func stateSource(isAvailable: Bool, origin: String?, permission: PageNotificationPermission) -> String {
        let quoted = origin.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        return "window['\(bridgeName)']?.setState(\(isAvailable), \(quoted), '\(permission.rawValue)');"
    }

    /// Function body, run in `world` (`callAsyncJavaScript`): the decision `state` of `origin` changed for the
    /// displayed document.
    static let stateBody = "window[bridge]?.setState(true, origin, state);"

    /// Function body, run in `world`, that sends `type` (“click”) to the notification `id` of the page
    /// (`callAsyncJavaScript`).
    static let dispatchBody = "window[bridge]?.dispatch(id, type);"

    static let worldSource = """
    (() => {
        const handler = window.webkit?.messageHandlers?.\(handlerName);
        if (!handler) {
            return;
        }
        const origin = self.origin;
        const isMainFrame = window.top === window;
        const isTopOrigin = (() => {
            try {
                return isMainFrame || window.top.location.origin === origin;
            } catch {
                return false;
            }
        })();
        let available = false;
        let states = {};
        const permission = () => (available && window.isSecureContext && isTopOrigin ? states[origin] ?? 'default' : 'denied');
        const send = (detail) => window.dispatchEvent(new CustomEvent('\(toPage)', { detail: JSON.stringify(detail) }));
        window.addEventListener('\(toWorld)', (event) => {
            let message;
            try {
                message = JSON.parse(event.detail);
            } catch {
                return;
            }
            const reply = (result) => send({ call: message?.call, result });
            switch (message?.type) {
            case 'permission':
                reply(permission());
                break;
            case 'request':
                if (permission() !== 'default' || !isMainFrame || navigator.userActivation?.isActive !== true) {
                    reply(permission());
                    break;
                }
                handler.postMessage({ type: 'request' }).then((answer) => {
                    if (answer === 'granted' || answer === 'denied') {
                        states[origin] = answer;
                    }
                    reply(permission());
                }, () => reply(permission()));
                break;
            case 'show':
                if (permission() !== 'granted') {
                    reply(false);
                    break;
                }
                handler.postMessage({
                    type: 'show',
                    id: String(message.id),
                    title: String(message.title),
                    body: String(message.body ?? ''),
                    tag: String(message.tag ?? ''),
                    silent: message.silent === true,
                }).then((ok) => reply(ok === true), () => reply(false));
                break;
            case 'close':
                handler.postMessage({ type: 'close', id: String(message.id) }).catch(() => {});
                break;
            default:
                reply(null);
            }
        }, true);
        Object.defineProperty(window, '\(bridgeName)', {
            value: Object.freeze({
                setState(isAvailable, website, state) {
                    available = isAvailable === true;
                    if (typeof website === 'string' && ['granted', 'denied', 'default'].includes(state)) {
                        states[website] = state;
                    }
                },
                dispatch(id, type) {
                    send({ event: String(type), id: String(id) });
                },
            }),
        });
    })();
    """

    static let pageSource = """
    (() => {
        if (typeof window.Notification === 'undefined') {
            return;
        }
        const dispatch = window.dispatchEvent.bind(window);
        const Custom = window.CustomEvent;
        const { parse, stringify } = JSON;
        const waiting = new Map();
        const shown = new Map();
        let calls = 0;
        const fire = (target, type) => {
            const event = new Event(type);
            target.dispatchEvent(event);
            const listener = target['on' + type];
            if (typeof listener === 'function') {
                listener.call(target, event);
            }
        };
        window.addEventListener('\(toPage)', (event) => {
            let message;
            try {
                message = parse(event.detail);
            } catch {
                return;
            }
            if (typeof message?.event === 'string') {
                const notification = shown.get(message.id);
                if (notification) {
                    fire(notification, message.event);
                }
                return;
            }
            const callback = waiting.get(message?.call);
            if (callback) {
                waiting.delete(message.call);
                callback(message.result);
            }
        }, true);
        const post = (message, callback) => {
            const call = ++calls;
            if (callback) {
                waiting.set(call, callback);
            }
            dispatch(new Custom('\(toWorld)', { detail: stringify({ ...message, call }) }));
            return call;
        };
        const ask = (message) => new Promise((resolve) => post(message, resolve));
        const permission = () => {
            let result = 'denied';
            waiting.delete(post({ type: 'permission' }, (answer) => { result = answer; }));
            return ['granted', 'denied', 'default'].includes(result) ? result : 'denied';
        };
        class Notification extends EventTarget {
            #id = Math.random().toString(36).slice(2, 12) + Date.now().toString(36);
            #title;
            #options;
            constructor(title, options) {
                super();
                if (arguments.length === 0) {
                    throw new TypeError("Failed to construct 'Notification': 1 argument required, but only 0 present.");
                }
                this.#title = String(title);
                this.#options = options && typeof options === 'object' ? { ...options } : {};
                this.onclick = null;
                this.onshow = null;
                this.onclose = null;
                this.onerror = null;
                if (permission() !== 'granted') {
                    setTimeout(() => fire(this, 'error'));
                    return;
                }
                shown.set(this.#id, this);
                ask({ type: 'show', id: this.#id, title: this.#title, body: this.body, tag: this.tag, silent: this.silent })
                    .then((ok) => fire(this, ok === true ? 'show' : 'error'));
            }
            get title() { return this.#title; }
            get body() { return String(this.#options.body ?? ''); }
            get tag() { return String(this.#options.tag ?? ''); }
            get icon() { return String(this.#options.icon ?? ''); }
            get badge() { return String(this.#options.badge ?? ''); }
            get image() { return String(this.#options.image ?? ''); }
            get dir() { return this.#options.dir ?? 'auto'; }
            get lang() { return String(this.#options.lang ?? ''); }
            get data() { return this.#options.data ?? null; }
            get silent() { return this.#options.silent === true; }
            get renotify() { return this.#options.renotify === true; }
            get requireInteraction() { return this.#options.requireInteraction === true; }
            get actions() { return []; }
            close() {
                if (shown.delete(this.#id)) {
                    post({ type: 'close', id: this.#id });
                    setTimeout(() => fire(this, 'close'));
                }
            }
            static get permission() { return permission(); }
            static get maxActions() { return 0; }
            static async requestPermission(callback) {
                let result = permission();
                if (result === 'default') {
                    // Sent at once, still within the click: the isolated script checks it.
                    const answer = await ask({ type: 'request' });
                    if (answer === 'granted' || answer === 'denied' || answer === 'default') {
                        result = answer;
                    }
                }
                if (typeof callback === 'function') {
                    callback(result);
                }
                return result;
            }
        }
        Object.defineProperty(window, 'Notification', { value: Notification, writable: true, configurable: true });
        const permissions = navigator.permissions;
        if (permissions?.query) {
            const query = permissions.query.bind(permissions);
            permissions.query = (descriptor) => {
                if (descriptor?.name !== 'notifications') {
                    return query(descriptor);
                }
                const status = new EventTarget();
                status.onchange = null;
                Object.defineProperty(status, 'name', { value: 'notifications' });
                Object.defineProperty(status, 'state', { get: () => ({ granted: 'granted', denied: 'denied' })[permission()] ?? 'prompt' });
                return Promise.resolve(status);
            };
        }
        const registration = window.ServiceWorkerRegistration?.prototype;
        if (registration) {
            registration.showNotification = (title, options) => {
                if (permission() !== 'granted') {
                    return Promise.reject(new TypeError('No notification permission has been granted for this origin.'));
                }
                new Notification(title, options);
                return Promise.resolve();
            };
            registration.getNotifications = () => Promise.resolve([]);
        }
    })();
    """
}
