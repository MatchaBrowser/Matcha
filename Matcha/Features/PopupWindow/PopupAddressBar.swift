import SwiftUI

/// Address bar of a sign-in window (task 5.8), read-only: the page's site and, for a site, whether the connection
/// is encrypted (padlock) or not (“Not Secure”). You must see who you are giving your password to: the page only
/// chooses the window title, never this bar. The full address is in the help tag.
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
        // Full address of a site only: that of a `data:` page can contain the whole page.
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
