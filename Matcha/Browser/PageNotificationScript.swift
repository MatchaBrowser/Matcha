import Foundation
import OSLog
import WebKit

/// Matcha's own `Notification` in the pages: WebKit offers no public API to grant notifications (its own answers
/// “denied” to every request while still saying “default”, so websites ask again on every load). Injected at the start
/// of each document, in the page's world (the page must see it), it replaces `Notification`,
/// `navigator.permissions.query({ name: 'notifications' })` and `ServiceWorkerRegistration.showNotification` (from the
/// page; a service worker's own notifications stay out of reach), and talks to the app through
/// `PageNotificationMessageHandler`. The permission it shows comes from a state script added by the app before each
/// navigation (`stateSource`): the decisions of the profile, known from the start of the document. A request is only
/// sent right after a click or a key press, as in Safari; a cross-origin frame or an insecure page reads “denied”.
@MainActor
enum PageNotificationScript {
    static let handlerName = "matchaNotifications"
    /// Property of `window` through which the app reaches the script (states, events); random for each launch.
    static let bridgeName = "__matchaNotifications" + UUID().uuidString.replacingOccurrences(of: "-", with: "")

    /// Hooks the script and its recipient onto `controller` (once per controller, like the sound script).
    static func install(in controller: WKUserContentController) {
        controller.addScriptMessageHandler(PageNotificationMessageHandler(), contentWorld: .page, name: handlerName)
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false, in: .page))
    }

    /// State script: notifications available or not (private window), and the decision of each origin, read by the
    /// script injected before it.
    static func stateSource(isAvailable: Bool, states: [String: PageNotificationPermission]) -> String {
        let object = states.mapValues(\.rawValue)
        let json = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return "window['\(bridgeName)']?.setStates(\(isAvailable), \(json));"
    }

    /// Function body that sends `type` (“click”) to the notification `id` of the page (`callAsyncJavaScript`).
    static let dispatchBody = "window[bridge]?.dispatch(id, type);"

    static let source = """
    (() => {
        const handler = window.webkit?.messageHandlers?.\(handlerName);
        if (!handler || typeof window.Notification === 'undefined') {
            return;
        }
        const origin = self.origin;
        const isTopOrigin = (() => {
            try {
                return window.top === window || window.top.location.origin === origin;
            } catch {
                return false;
            }
        })();
        let available = false;
        let states = {};
        const permission = () => (available && window.isSecureContext && isTopOrigin ? states[origin] ?? 'default' : 'denied');
        const shown = new Map();
        const fire = (target, type) => {
            const event = new Event(type);
            target.dispatchEvent(event);
            const listener = target['on' + type];
            if (typeof listener === 'function') {
                listener.call(target, event);
            }
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
                handler.postMessage({ type: 'show', id: this.#id, title: this.#title, body: this.body, tag: this.tag, silent: this.silent })
                    .then((ok) => fire(this, ok ? 'show' : 'error'), () => fire(this, 'error'));
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
                    handler.postMessage({ type: 'close', id: this.#id }).catch(() => {});
                    setTimeout(() => fire(this, 'close'));
                }
            }
            static get permission() { return permission(); }
            static get maxActions() { return 0; }
            static async requestPermission(callback) {
                let result = permission();
                if (result === 'default' && navigator.userActivation?.isActive !== false) {
                    try {
                        const answer = await handler.postMessage({ type: 'request' });
                        if (answer === 'granted' || answer === 'denied') {
                            states[origin] = answer;
                            result = answer;
                        }
                    } catch {}
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
        Object.defineProperty(window, '\(bridgeName)', {
            value: Object.freeze({
                setStates(isAvailable, newStates) {
                    available = isAvailable === true;
                    states = { ...newStates };
                },
                dispatch(id, type) {
                    const notification = shown.get(id);
                    if (notification) {
                        fire(notification, type);
                    }
                },
            }),
        });
    })();
    """
}

/// Receives the messages of the notification script and hands them to the navigation delegate of the page that sends
/// them (`NavigationCoordinator+Notifications`), which answers. A malformed message, or one from a page without a
/// delegate, gets a refusal.
final class PageNotificationMessageHandler: NSObject, WKScriptMessageHandlerWithReply {
    func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void,
    ) {
        guard let parsed = PageNotificationMessage(body: message.body) else {
            Logger.notifications.notice("Malformed notification script message: refused")
            replyHandler(nil, "Malformed message")
            return
        }
        guard let webView = message.webView, let coordinator = webView.navigationDelegate as? NavigationCoordinator else {
            replyHandler(nil, "No page")
            return
        }
        coordinator.receive(parsed, from: message.frameInfo, in: webView) { replyHandler($0, nil) }
    }
}
