import SwiftUI

/// The vault's button in the address pill (`VAULT.md` § 8.1): shown on a page with a login form; its list, native,
/// out of the page, proposes the logins of the site, frame by frame. Nothing is filled until one is chosen (⌘\).
struct VaultFillButton: View {
    let tab: BrowserTab
    @Environment(VaultService.self) private var vault: VaultService?
    @State private var isShown = false

    var body: some View {
        if let vault, vault.isOffered, tab.vaultForms.hasLoginForm {
            Button {
                isShown.toggle()
            } label: {
                Image(systemName: "key.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut("\\", modifiers: .command)
            .help(String(localized: "Fill a Password", comment: "Address pill: button of the vault's filling"))
            .popover(isPresented: $isShown, arrowEdge: .bottom) {
                VaultFillList(tab: tab, vault: vault, done: { isShown = false })
            }
        }
    }
}

/// The logins that match each frame with a form, the main one first; the vault opens here if it is locked.
struct VaultFillList: View {
    let tab: BrowserTab
    let vault: VaultService
    let done: () -> Void
    @Environment(\.openWindow) private var openWindow
    @Environment(\.vaultClipboard) private var clipboard
    @State private var password = ""
    @State private var error: (any Error)?
    /// A password for a sign-up form, drawn when the list opens (`VAULT.md` § 8.4).
    @State private var suggestion = (try? PasswordGenerator())?.generate() ?? ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if vault.isUnlocked {
                candidates
            } else {
                unlock
            }
            Divider()
            Button(String(localized: "Open the Vault", comment: "Vault filling: opens the vault's window")) {
                openWindow(id: MatchaApp.vaultWindowID)
                done()
            }
            .buttonStyle(.link)
        }
        .padding(12)
        .frame(width: 320)
        .onAppear { vault.noteActivity() }
    }

    @ViewBuilder private var candidates: some View {
        if let signup = tab.vaultForms.fillableFrames.first(where: \.isSignup), !suggestion.isEmpty {
            Text("A strong password for this form", comment: "Vault filling: a generated password for a sign-up form")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Text(suggestion).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button(String(localized: "Use", comment: "Vault generator: put the password in the field")) { fillNew(in: signup) }
            }
            Divider()
        }
        let frames = tab.vaultForms.fillableFrames
        let lists = frames.map { ($0, vault.logins(for: $0.isMainFrame ? (tab.documentURL ?? $0.url) : $0.url)) }
        if lists.allSatisfy(\.1.isEmpty) {
            Text("No login of the vault for this site.", comment: "Vault filling: nothing matches")
                .foregroundStyle(.secondary)
        }
        ForEach(lists.indices, id: \.self) { index in
            let (frame, logins) = lists[index]
            if !logins.isEmpty {
                if !frame.isMainFrame {
                    Text("In a frame of \(frame.url.host() ?? frame.origin)", comment: "Vault filling: logins for a frame of another site")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(logins) { candidate in
                    Button {
                        fill(candidate, in: frame)
                    } label: {
                        VaultFillRow(candidate: candidate)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder private var unlock: some View {
        Text("The vault is locked", comment: "Vault window: title of the lock screen")
            .font(.headline)
        SecureField(String(localized: "Master Password", comment: "Vault window: password field"), text: $password)
            .onSubmit(unlockWithPassword)
        if let error {
            Text(VaultErrorText.message(for: error)).foregroundStyle(.red).font(.caption)
        }
        HStack {
            if vault.canUnlockWithTouchID(bootDate: Date.now.addingTimeInterval(-ProcessInfo.processInfo.systemUptime)) {
                Button(String(localized: "Use Touch ID", comment: "Vault window: button of the lock screen")) {
                    Task { try? await vault.unlockWithTouchID(reason: String(
                        localized: "open the vault",
                        comment: "Touch ID prompt: Matcha wants to…",
                    )) }
                }
            }
            Button(String(localized: "Unlock", comment: "Vault window: button of the lock screen"), action: unlockWithPassword)
                .disabled(password.isEmpty)
        }
    }

    private func unlockWithPassword() {
        let typed = password
        Task {
            do {
                try await vault.unlock(password: typed)
                (password, error) = ("", nil)
            } catch {
                self.error = error
            }
        }
    }

    /// Fills the generated password; the save bar offers it after the form is sent.
    private func fillNew(in frame: VaultPageForms.Frame) {
        guard let webView = tab.webView else {
            return
        }
        let password = suggestion
        done()
        Task { _ = await VaultFiller.fillNewPassword(password, in: frame, webView: webView) }
    }

    /// Fills the frame; a one-time code is filled if the page has a field for it, copied otherwise.
    private func fill(_ candidate: VaultFillCandidate, in frame: VaultPageForms.Frame) {
        guard let webView = tab.webView, let values = try? vault.fillValues(of: candidate.id) else {
            return
        }
        vault.noteActivity()
        done()
        Task {
            _ = await VaultFiller.fill(frame, in: webView, username: values.username, password: values.password)
            if let code = values.code, await !(VaultFiller.fillCode(code, in: frame, webView: webView)) {
                clipboard?.copy(code)
            }
        }
    }
}

/// A login of the list: its title, its user name, a warning on an insecure page.
struct VaultFillRow: View {
    let candidate: VaultFillCandidate

    var body: some View {
        HStack {
            Image(systemName: "key.fill").foregroundStyle(.secondary)
            VStack(alignment: .leading) {
                Text(candidate.item.overview.title).lineLimit(1)
                Text(candidate.item.overview.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if candidate.result == .insecureMatch {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(String(
                        localized: "This page isn't secure: what you fill can be read on the network.",
                        comment: "Vault filling: an http page",
                    ))
            }
        }
        .contentShape(.rect)
    }
}
