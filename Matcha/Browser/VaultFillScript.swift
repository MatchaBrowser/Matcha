import Foundation
import WebKit

/// The script of the vault's filling (`VAULT.md` § 8.3), in a content world of its own that the page doesn't see: it
/// tells the app which frames have a login form, and which form was sent (to offer saving); it fills only when the app
/// calls it, for one frame, after checking again that the frame's origin is the one expected. It never fills by itself.
@MainActor
enum VaultFillScript {
    static let world = WKContentWorld.world(name: "MatchaVaultFill")
    static let handlerName = "matchaVault"

    /// Whether the pages talk to the filling: not while the vault is turned off on this Mac (`VaultService.isEnabled`).
    private(set) static var isEnabled = true

    static func install(in controller: WKUserContentController) {
        controller.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: false, in: world))
        if isEnabled {
            controller.add(VaultFillMessageHandler(), contentWorld: world, name: handlerName)
        }
    }

    /// Connects or disconnects a page's controller: without its handler, the script stops as soon as it starts, from
    /// the page's next load; a page already loaded can no longer post anything.
    static func setEnabled(_ enabled: Bool, in controller: WKUserContentController) {
        controller.removeScriptMessageHandler(forName: handlerName, contentWorld: world)
        if enabled {
            controller.add(VaultFillMessageHandler(), contentWorld: world, name: handlerName)
        }
    }

    /// For every page: those made from now on, and those of `controllers`.
    static func setEnabled(_ enabled: Bool, in controllers: [WKUserContentController]) {
        isEnabled = enabled
        for controller in controllers {
            setEnabled(enabled, in: controller)
        }
    }

    /// Fills a login in the frame; `expected` is the origin Matcha checked (`scheme://host[:port]`).
    static let fillBody = "return window.__matchaVaultFill?.(username, password, expected) ?? false;"
    /// Fills a one-time code in the frame.
    static let fillCodeBody = "return window.__matchaVaultFillCode?.(code, expected) ?? false;"
    /// Fills a new password (sign-up, change of password): its fields, and their confirmation.
    static let fillNewBody = "return window.__matchaVaultFillNew?.(password, expected) ?? false;"

    static let source = """
    (() => {
        const handler = window.webkit?.messageHandlers?.\(handlerName);
        if (!handler || window.__matchaVaultFill) {
            return;
        }
        const visible = (element) => {
            if (!element || element.disabled || element.readOnly) {
                return false;
            }
            const style = getComputedStyle(element);
            return style.visibility !== 'hidden' && style.display !== 'none' && element.getClientRects().length > 0;
        };
        const passwords = () => Array.from(document.querySelectorAll('input[type=password]')).filter(visible);
        const textTypes = ['text', 'email', 'tel', ''];
        const usernameFor = (password) => {
            const scope = password.form || document;
            const inputs = Array.from(scope.querySelectorAll('input')).filter((input) => visible(input) && textTypes.includes(input.type));
            const hinted = inputs.find((input) => /\\b(username|email)\\b/.test(input.autocomplete || ''));
            if (hinted) {
                return hinted;
            }
            let candidate = null;
            for (const input of inputs) {
                if (input.compareDocumentPosition(password) & Node.DOCUMENT_POSITION_FOLLOWING) {
                    candidate = input;
                }
            }
            return candidate;
        };
        const loneUsername = () => Array.from(document.querySelectorAll(
            'input[autocomplete~=username], input[type=email], input[name*=user i], input[name*=login i], input[id*=user i]'
        )).find(visible);
        let reported = null;
        const report = () => {
            const fields = passwords();
            const state = {
                type: 'forms',
                hasPassword: fields.length > 0,
                hasUsername: fields.length === 0 && !!loneUsername(),
                isSignup: fields.length > 1 || fields.some((field) => field.autocomplete === 'new-password'),
            };
            const key = JSON.stringify(state);
            if (key !== reported) {
                reported = key;
                handler.postMessage(state);
            }
        };
        let scheduled = false;
        const schedule = () => {
            if (!scheduled) {
                scheduled = true;
                setTimeout(() => { scheduled = false; report(); }, 300);
            }
        };
        new MutationObserver(schedule).observe(document.documentElement, {
            childList: true, subtree: true, attributes: true, attributeFilter: ['type', 'style', 'class'],
        });
        schedule();
        const capture = (form) => {
            const fields = form ? Array.from(form.querySelectorAll('input[type=password]')) : passwords();
            const field = fields.find((input) => input.value);
            if (!field) {
                return;
            }
            const user = usernameFor(field);
            handler.postMessage({
                type: 'submitted',
                username: (user?.value ?? '').slice(0, 512),
                password: field.value.slice(0, 1024),
                isSignup: fields.length > 1 || field.autocomplete === 'new-password',
            });
        };
        document.addEventListener('submit', (event) => capture(event.target), true);
        document.addEventListener('keydown', (event) => {
            if (event.key === 'Enter' && event.target?.type === 'password') {
                capture(event.target.form);
            }
        }, true);
        document.addEventListener('click', (event) => {
            const button = event.target?.closest?.('button, input[type=submit]');
            if (button && (button.type === 'submit' || button.form)) {
                capture(button.form);
            }
        }, true);
        const setValue = (input, value) => {
            input.focus();
            Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, value);
            input.dispatchEvent(new Event('input', { bubbles: true }));
            input.dispatchEvent(new Event('change', { bubbles: true }));
        };
        // The frame may have changed page since Matcha checked it: nothing is filled for another origin.
        const isExpected = (expected) => self.origin !== 'null' && self.origin === expected;
        window.__matchaVaultFill = (username, password, expected) => {
            if (!isExpected(expected)) {
                return false;
            }
            const field = passwords()[0];
            if (field) {
                const user = usernameFor(field);
                if (user && username) {
                    setValue(user, username);
                }
                if (password) {
                    setValue(field, password);
                }
                return true;
            }
            const user = loneUsername();
            if (user && username) {
                setValue(user, username);
                return true;
            }
            return false;
        };
        window.__matchaVaultFillNew = (password, expected) => {
            if (!isExpected(expected)) {
                return false;
            }
            const fields = passwords();
            const fresh = fields.filter((field) => field.autocomplete === 'new-password');
            const targets = fresh.length > 0 ? fresh : fields;
            targets.forEach((field) => setValue(field, password));
            return targets.length > 0;
        };
        window.__matchaVaultFillCode = (code, expected) => {
            if (!isExpected(expected)) {
                return false;
            }
            const field = Array.from(document.querySelectorAll(
                'input[autocomplete=one-time-code], input[name*=otp i], input[name*=code i], input[id*=otp i], input[inputmode=numeric]'
            )).find(visible);
            if (!field) {
                return false;
            }
            setValue(field, code);
            return true;
        };
    })();
    """
}
