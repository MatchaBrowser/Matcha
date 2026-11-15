import Foundation

extension VaultFillScript {
    /// Finds the login fields of the frame, those of open shadow roots (Web Components) included, and tells the app
    /// when they change: a password field, a lone user name field (the first step of a login in two pages), a sign-up.
    static let formsSource = """
        const handler = window.webkit?.messageHandlers?.\(handlerName);
        if (!handler || window.__matchaVaultFill) {
            return;
        }
        const startedAt = Date.now();
        // The document and the open shadow roots found in it: their fields count, and their changes are watched.
        const roots = [document];
        const knownRoots = new WeakSet();
        const watched = { childList: true, subtree: true, attributes: true, attributeFilter: ['type', 'style', 'class', 'hidden'] };
        let scheduled = false;
        const schedule = () => {
            if (!scheduled) {
                scheduled = true;
                setTimeout(() => { scheduled = false; report(); }, 300);
            }
        };
        const observer = new MutationObserver((records) => {
            for (const record of records) {
                record.addedNodes.forEach((node) => {
                    if (node.nodeType === Node.ELEMENT_NODE) {
                        discover(node);
                    }
                });
            }
            schedule();
        });
        const onSubmit = [];
        // Run at each report: the parts that follow a field check it is still there.
        const onReport = [];
        const discover = (start) => {
            const walker = document.createTreeWalker(start, NodeFilter.SHOW_ELEMENT);
            for (let node = walker.currentNode; node; node = walker.nextNode()) {
                const root = node.shadowRoot;
                if (root && !knownRoots.has(root)) {
                    knownRoots.add(root);
                    roots.push(root);
                    observer.observe(root, watched);
                    // `submit` doesn't leave its shadow root: listened to in each one.
                    onSubmit.forEach((listener) => root.addEventListener('submit', listener, true));
                    discover(root);
                }
            }
        };
        const queryAll = (selector) => roots
            .filter((root) => root === document || root.host.isConnected)
            .flatMap((root) => Array.from(root.querySelectorAll(selector)));
        const isShown = (element) => element.isConnected && element.getClientRects().length > 0
            && getComputedStyle(element).visibility !== 'hidden';
        const visible = (element) => !!element && !element.disabled && !element.readOnly && isShown(element);
        const passwords = () => queryAll('input[type=password]').filter(visible);
        const textTypes = ['text', 'email', 'tel'];
        const usernameWords = /user|login|e-?mail|account|identifier|signin/i;
        const notUsername = /search|newsletter|subscribe|coupon|promo/i;
        const isTextField = (input) => textTypes.includes(input.type) && visible(input)
            && !notUsername.test(`${input.name} ${input.id} ${input.placeholder}`);
        const isUsernameLike = (input) => /\\b(username|email)\\b/.test(input.autocomplete || '') || input.type === 'email'
            || usernameWords.test(input.name || '') || usernameWords.test(input.id || '');
        // The element of the document that holds `node` (its outermost shadow host): fields are ordered across roots.
        const lift = (node) => {
            let current = node;
            while (current.getRootNode() instanceof ShadowRoot) {
                current = current.getRootNode().host;
            }
            return current;
        };
        const precedes = (first, second) => {
            const [outerFirst, outerSecond] = [lift(first), lift(second)];
            const [a, b] = outerFirst === outerSecond ? [first, second] : [outerFirst, outerSecond];
            return a !== b && !!(a.compareDocumentPosition(b) & Node.DOCUMENT_POSITION_FOLLOWING);
        };
        // The user name field of a password: a hinted one before it, any hinted one, or the last text field before it.
        const pickUsername = (inputs, password) => {
            const fields = inputs.filter(isTextField);
            const before = fields.filter((input) => precedes(input, password));
            return before.filter(isUsernameLike).pop() ?? fields.find(isUsernameLike) ?? before.pop() ?? null;
        };
        const usernameFor = (password) => (password.form && pickUsername(Array.from(password.form.querySelectorAll('input')), password))
            || pickUsername(queryAll('input'), password);
        const loneUsername = () => queryAll('input').find((input) => isTextField(input) && isUsernameLike(input));
        let lastFullScan = 0;
        let reported = null;
        const report = () => {
            onReport.forEach((check) => check());
            let fields = passwords();
            const now = Date.now();
            if (fields.length === 0 && now - startedAt < 30000 && now - lastFullScan > 2000) {
                // A shadow root attached after its element was inserted (a component defined late) shows at a new scan.
                lastFullScan = now;
                discover(document.documentElement);
                fields = passwords();
            }
            const state = {
                type: 'forms',
                hasPassword: fields.length > 0,
                hasUsername: fields.length === 0 && !!loneUsername(),
                isSignup: fields.some((field) => field.autocomplete === 'new-password'
                    || (field.form && fields.filter((other) => other.form === field.form).length > 1)),
            };
            const key = JSON.stringify(state);
            if (key !== reported) {
                reported = key;
                handler.postMessage(state);
            }
        };

    """
}
