import Foundation

extension VaultFillScript {
    /// Tells the app which login field the user just reached, for its native list under the field (`VAULT.md` § 8.1):
    /// a field clicked (a real click: the page can't make one), or focused within 2 seconds of a real click or key (Tab,
    /// or the click that opened a login dialog), never a focus the page gives alone. Real: `isTrusted`, which the page
    /// can't fake; not `navigator.userActivation`, which the app's own calls into the page turn on. Its box, in CSS
    /// pixels of the main frame's viewport, places the list; typing, a click elsewhere, a scroll or a resize withdraw
    /// it. Not in a frame, nor on a pinched page: the address pill's key stays there.
    static let suggestSource = """
        let suggested = null;
        let pendingOffer = null;
        let lastInput = 0;
        const focusedField = () => {
            let element = document.activeElement;
            while (element?.shadowRoot?.activeElement) {
                element = element.shadowRoot.activeElement;
            }
            return element;
        };
        const isLoginField = (input) => {
            if (!(input instanceof HTMLInputElement) || !visible(input)) {
                return false;
            }
            const fields = passwords().filter((field) => field.autocomplete !== 'new-password');
            if (input.type === 'password') {
                return fields.includes(input);
            }
            return fields.length > 0 ? fields.some((field) => usernameFor(field) === input) : loneUsername() === input;
        };
        const offer = (input) => {
            const viewport = window.visualViewport;
            if (window !== window.top || (viewport && viewport.scale !== 1)) {
                return;
            }
            const box = input.getBoundingClientRect();
            suggested = input;
            handler.postMessage({
                type: 'field', x: box.left, y: box.top, width: box.width, height: box.height,
                viewportWidth: window.innerWidth, viewportHeight: window.innerHeight,
            });
        };
        const hide = () => {
            if (suggested) {
                suggested = null;
                handler.postMessage({ type: 'fieldDone' });
            }
        };
        const withdraw = () => {
            clearTimeout(pendingOffer);
            hide();
        };
        onReport.push(() => {
            if (suggested && !visible(suggested)) {
                withdraw();
            }
        });
        document.addEventListener('pointerdown', (event) => {
            if (!event.isTrusted) {
                return;
            }
            lastInput = Date.now();
            const field = event.composedPath()[0];
            if (isLoginField(field)) {
                clearTimeout(pendingOffer);
                offer(field);
            } else {
                withdraw();
            }
        }, true);
        document.addEventListener('focusin', (event) => {
            const field = event.composedPath()[0];
            if (field === suggested || Date.now() - lastInput > 2000 || !(field instanceof HTMLInputElement)) {
                return;
            }
            clearTimeout(pendingOffer);
            // A dialog opened by a click may still be moving: the field is measured once it has settled.
            pendingOffer = setTimeout(() => {
                if (focusedField() === field && isLoginField(field)) {
                    offer(field);
                }
            }, 250);
        }, true);
        const modifiers = ['Shift', 'Control', 'Alt', 'Meta', 'CapsLock', 'Fn'];
        document.addEventListener('keydown', (event) => {
            if (event.isTrusted) {
                lastInput = Date.now();
            }
            if (!modifiers.includes(event.key)) {
                withdraw();
            }
        }, true);
        window.addEventListener('scroll', hide, true);
        window.addEventListener('resize', hide);

    """
}
