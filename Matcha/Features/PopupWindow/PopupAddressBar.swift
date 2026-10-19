import SwiftUI

/// Address bar of a sign-in window (task 5.8), read-only: the page's site and, for a site, whether the connection
/// is encrypted (padlock, which shows the certificate) or not (“Not Secure”). You must see who you are giving your password to: the page
/// only
/// chooses the window title, never this bar. The full address is in the help tag.
struct PopupAddressBar: View {
    static let height = 30.0

    let page: BrowserTab

    var body: some View {
        let address = PopupAddress(url: page.displayedURL)
        HStack(spacing: 6) {
            Text(verbatim: address.text)
                .lineLimit(1)
                .truncationMode(.middle)
                .accessibilityLabel(Text("Address", comment: "Accessibility label of the address pill"))
                .accessibilityValue(Text(verbatim: address.text))
                .accessibilityIdentifier("popupAddress")
            // Padlock that shows the certificate, or “Not Secure” in red: a password may be typed here (audit W5).
            PageSecurityIndicator(page: page, prominent: true)
                .layoutPriority(1)
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
        .help(Text(verbatim: address.security == .none ? address.text : page.displayedURL?.absoluteString ?? ""))
        .accessibilityElement(children: .contain)
    }
}
