import SwiftUI

/// Security of a page next to its address (audit W5): a padlock button that shows the certificate of an encrypted
/// page; “Not Secure” for an unencrypted one, in red (and showing the certificate) for a website visited despite its
/// invalid certificate (audit K5); “Local File” for a local file, whose name could pass for a website's
/// (“www.paypal.com.html”, review WB14); nothing for another page that isn't a website. `prominent`: in red, where a
/// password may be typed (sign-in windows).
struct PageSecurityIndicator: View {
    let page: BrowserTab
    var showsNotSecureText = true
    var prominent = false

    var body: some View {
        switch page.security {
        case .secure, .partlySecure:
            Button {
                CertificatePanel.show(for: page, in: NSApp.keyWindow)
            } label: {
                Image(systemName: page.security == .secure ? "lock.fill" : "lock.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, height: 18)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(helpText)
            .accessibilityLabel(helpText)
            .accessibilityIdentifier("certificateButton")
        case .notSecure:
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                if showsNotSecureText {
                    Text("Not Secure", comment: "Address bar: the page is not encrypted (http)")
                        .lineLimit(1)
                }
            }
            .foregroundStyle(prominent ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
            .help(Text(
                "The connection to this site isn't encrypted. Don't enter passwords or payment details.",
                comment: "Help tag of “Not Secure” in the address bar",
            ))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Not Secure", comment: "Address bar: the page is not encrypted (http)"))
            .accessibilityIdentifier("notSecureLabel")
        case .invalidCertificate:
            // Visited despite its invalid certificate, at the user's request: “Not Secure” in red, which shows it.
            Button {
                CertificatePanel.show(for: page, in: NSApp.keyWindow)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .medium))
                    if showsNotSecureText {
                        Text("Not Secure", comment: "Address bar: the page is not encrypted (http)")
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(.red)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(invalidCertificateHelp)
            .accessibilityLabel(invalidCertificateHelp)
            .accessibilityIdentifier("invalidCertificateButton")
        case .none:
            if page.displayedURL?.isFileURL == true {
                localFile
            }
        }
    }

    private var localFile: some View {
        HStack(spacing: 4) {
            Image(systemName: "doc")
                .font(.system(size: 11, weight: .medium))
            if showsNotSecureText {
                Text("Local File", comment: "Address bar: the page is a local file, not a website")
                    .lineLimit(1)
            }
        }
        .foregroundStyle(.secondary)
        .help(Text("This page is a file on this Mac, not a website.", comment: "Help tag of “Local File” in the address bar"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Local File", comment: "Address bar: the page is a local file, not a website"))
        .accessibilityIdentifier("localFileLabel")
    }

    private var invalidCertificateHelp: Text {
        Text(
            "This Website's Certificate Isn't Valid — Show Certificate",
            comment: "Help tag of “Not Secure” for a website visited despite its invalid certificate",
        )
    }

    private var helpText: Text {
        page.security == .secure
            ? Text("Secure Connection — Show Certificate", comment: "Help tag of the padlock in the address bar")
            : Text(
                "Parts of This Page Aren't Encrypted — Show Certificate",
                comment: "Help tag of the padlock in the address bar, when images or media came without encryption",
            )
    }
}
