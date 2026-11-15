import Foundation

extension VaultFillScript {
    /// Tells the app which login was sent, to offer saving it (`VAULT.md` § 8.4). A form submitted is sent at once. A
    /// login sent by a script (a button that isn't a form's, Enter) waits until it succeeds: its password field is
    /// gone or hidden, or the address changed, or the page is left; given up after 20 seconds, a refused password stays
    /// in its field and is never offered. The user name of a first step is kept for the password of the next one.
    static let captureSource = """
        let pending = null;
        let remembered = '';
        const credentials = (form) => {
            const inForm = form ? Array.from(form.querySelectorAll('input[type=password]')) : [];
            const fields = inForm.length > 0 ? inForm : passwords();
            const field = fields.find((input) => input.value);
            if (!field) {
                return null;
            }
            const user = usernameFor(field);
            return {
                field,
                username: (user?.value || remembered).slice(0, 512),
                password: field.value.slice(0, 1024),
                isSignup: field.autocomplete === 'new-password' || fields.filter((input) => input.form === field.form).length > 1,
            };
        };
        const send = (login) => {
            pending = null;
            handler.postMessage({ type: 'submitted', username: login.username, password: login.password, isSignup: login.isSignup });
        };
        const rememberUsername = () => {
            const user = loneUsername();
            if (user?.value) {
                remembered = user.value.slice(0, 512);
                handler.postMessage({ type: 'username', username: remembered });
            }
        };
        let watching = null;
        const succeeded = (login) => location.href !== login.href || !isShown(login.field);
        const stage = (form) => {
            const login = credentials(form);
            if (!login) {
                rememberUsername();
                return;
            }
            pending = { ...login, at: Date.now(), href: location.href };
            clearInterval(watching);
            watching = setInterval(() => {
                if (!pending || Date.now() - pending.at > 20000) {
                    clearInterval(watching);
                    pending = null;
                } else if (succeeded(pending)) {
                    clearInterval(watching);
                    send(pending);
                }
            }, 400);
        };
        const submitted = (event) => {
            const login = credentials(event.target);
            if (login) {
                send(login);
            } else {
                rememberUsername();
            }
        };
        onSubmit.push(submitted);
        document.addEventListener('submit', submitted, true);
        document.addEventListener('keydown', (event) => {
            const field = event.composedPath()[0];
            if (event.key === 'Enter' && field instanceof HTMLInputElement) {
                stage(field.form);
            }
        }, true);
        const buttons = 'button, input[type=submit], input[type=button], input[type=image], [role=button]';
        document.addEventListener('click', (event) => {
            const button = event.composedPath().find((node) => node instanceof Element && node.matches(buttons));
            if (button) {
                stage(button.form ?? null);
            }
        }, true);
        window.addEventListener('pagehide', () => {
            if (pending) {
                send(pending);
            }
        });
        observer.observe(document.documentElement, watched);
        discover(document.documentElement);
        window.addEventListener('load', schedule);
        schedule();

    """

    /// Fills, only when the app calls it, after checking that the frame still has the origin the app checked.
    static let fillSource = """
        const setValue = (input, value) => {
            input.focus();
            Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(input, value);
            input.dispatchEvent(new Event('input', { bubbles: true, composed: true }));
            input.dispatchEvent(new Event('change', { bubbles: true, composed: true }));
        };
        // The frame may have changed page since Matcha checked it: nothing is filled for another origin.
        const isExpected = (expected) => self.origin !== 'null' && self.origin === expected;
        window.__matchaVaultFill = (username, password, expected) => {
            if (!isExpected(expected)) {
                return false;
            }
            // The list that was shown under a field closed with this choice.
            suggested = null;
            const fields = passwords();
            const field = fields.find((input) => input.autocomplete !== 'new-password') ?? fields[0];
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
            const field = queryAll(
                'input[autocomplete=one-time-code], input[name*=otp i], input[name*=code i], input[id*=otp i], input[inputmode=numeric]'
            ).find(visible);
            if (!field) {
                return false;
            }
            setValue(field, code);
            return true;
        };

    """
}
