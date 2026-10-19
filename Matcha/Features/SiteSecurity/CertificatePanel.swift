import AppKit
import OSLog
import SecurityInterface

/// Certificate of an encrypted page (audit W5): the system's certificate panel, as a sheet on the page's window, like
/// the padlock of Safari or Chrome. Read-only for the user: it shows who the site is and who vouches for it.
@MainActor
enum CertificatePanel {
    static func show(for page: BrowserTab, in window: NSWindow?) {
        guard let trust = page.serverTrust, let host = page.displayedURL?.host() else {
            NSSound.beep()
            return
        }
        let panel = SFCertificateTrustPanel()
        let message = page.security == .partlySecure
            ? String(
                localized: "The connection to “\(host)” is encrypted, but parts of this page were loaded without encryption.",
                comment: "Certificate panel of a page whose images or media are not encrypted; %@ is the website",
            )
            : String(
                localized: "Matcha is using an encrypted connection to “\(host)”.",
                comment: "Certificate panel of an encrypted page; %@ is the website",
            )
        panel.setInformativeText(String(
            localized: "Encryption with a digital certificate keeps information private as it's sent to or from this website.",
            comment: "Certificate panel: what the certificate is for",
        ))
        Logger.browser.info("Certificat affiché")
        if let window, window.isVisible, window.attachedSheet == nil {
            panel.beginSheet(for: window, modalDelegate: nil, didEnd: nil, contextInfo: nil, trust: trust, message: message)
        } else {
            panel.runModal(for: trust, message: message)
        }
    }
}
