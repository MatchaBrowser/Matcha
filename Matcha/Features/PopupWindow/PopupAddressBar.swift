import SwiftUI

/// Barre d'adresse d'une fenêtre de connexion (tâche 5.8), en lecture seule : le site de la page et, pour un site, si la
/// connexion est chiffrée (cadenas) ou non (« Non sécurisé »). On doit voir à qui l'on donne son mot de passe : la page
/// ne choisit que le titre de la fenêtre, jamais cette barre. L'adresse complète est dans la bulle d'aide.
struct PopupAddressBar: View {
    static let height = 30.0

    let page: BrowserTab

    var body: some View {
        let address = PopupAddress(url: page.url)
        HStack(spacing: 6) {
            security(address.security)
            Text(verbatim: address.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel(Text("Address", comment: "Accessibility label of the address pill"))
                .accessibilityValue(Text(verbatim: address.text))
                .accessibilityIdentifier("popupAddress")
            if address.security == .notSecure {
                Text("Not Secure", comment: "Sign-in window address bar: the page is not encrypted (http)")
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .layoutPriority(1)
                    .accessibilityIdentifier("popupNotSecure")
            }
            Spacer(minLength: 0)
            if page.isLoading {
                ProgressView().controlSize(.mini)
            }
        }
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        // Adresse complète d'un site seulement : celle d'une page `data:` peut contenir toute la page.
        .help(Text(verbatim: address.security == .none ? address.text : page.url?.absoluteString ?? ""))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private func security(_ security: PopupAddress.Security) -> some View {
        switch security {
        case .secure:
            Image(systemName: "lock.fill")
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(
                    "Secure Connection",
                    comment: "Sign-in window address bar: lock icon of an encrypted (https) page",
                ))
        case .notSecure:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .accessibilityHidden(true)
        case .none:
            EmptyView()
        }
    }
}
