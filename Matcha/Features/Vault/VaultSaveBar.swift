import SwiftUI

/// The native bar that offers to save, or update, the login a form just sent (`VAULT.md` § 8.4); never in a private
/// window (`VaultPageForms.isPrivate`). A locked vault opens first.
struct VaultSaveBar: View {
    let forms: VaultPageForms
    @Environment(VaultService.self) private var vault: VaultService?
    @Environment(\.openWindow) private var openWindow
    @State private var error: (any Error)?

    var body: some View {
        if let vault, let offer = forms.offer, vault.status == .locked || vault.status == .unlocked {
            let decision = vault.saveDecision(username: offer.username, password: offer.password, url: offer.url)
            if decision != .none {
                HStack(spacing: 10) {
                    Image(systemName: "key.fill").foregroundStyle(.tint)
                    Text(title(decision, offer: offer)).lineLimit(2)
                    if let error {
                        Text(VaultErrorText.message(for: error)).foregroundStyle(.red).font(.caption)
                    }
                    Spacer()
                    Button(String(localized: "Never for This Site", comment: "Vault save bar")) {
                        vault.neverSave(on: offer.url)
                        forms.offer = nil
                    }
                    Button(String(localized: "Not Now", comment: "Vault: refuse Touch ID")) { forms.offer = nil }
                    Button(saveTitle(decision)) { save(offer, decision: decision, in: vault) }
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
    }

    private func saveTitle(_ decision: VaultSaveDecision) -> String {
        decision == .save
            ? String(localized: "Save", comment: "Vault editor")
            : String(localized: "Update", comment: "Vault save bar: change the saved password")
    }

    private func title(_ decision: VaultSaveDecision, offer: VaultPageForms.SaveOffer) -> String {
        let host = offer.url.host() ?? offer.url.absoluteString
        if case .update = decision {
            return String(localized: "Update the password saved for \(host)?", comment: "Vault save bar")
        }
        return String(localized: "Save the password for \(host) in the vault?", comment: "Vault save bar")
    }

    private func save(_ offer: VaultPageForms.SaveOffer, decision: VaultSaveDecision, in vault: VaultService) {
        guard vault.isUnlocked else {
            openWindow(id: MatchaApp.vaultWindowID)
            return
        }
        do {
            let updating: UUID? = if case let .update(id) = decision {
                id
            } else {
                nil
            }
            try vault.saveLogin(username: offer.username, password: offer.password, url: offer.url, updating: updating)
            forms.offer = nil
        } catch {
            self.error = error
        }
    }
}
