import SwiftUI

/// Shown in place of a page that couldn't load (audit K5): why, in words, with “Try Again” (like ⌘R) and, for a
/// certificate that isn't valid, “Show Certificate” and, set apart in red, “Visit This Website Anyway”. Same style as the
/// message of a crashed page; it covers the page (card of a pane, peek, mini window, sign-in window) and takes its
/// clicks.
struct PageLoadErrorView: View {
    let page: BrowserTab
    let error: PageLoadError
    /// Makes the page active (pane of a split) when the message or its buttons are clicked.
    var activate: () -> Void = {}

    var body: some View {
        ContentUnavailableView {
            Label { title } icon: { Image(systemName: symbolName) }
        } description: {
            description
        } actions: {
            // One block: the usual buttons on a line, the red one alone below them, centered.
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    if error.kind == .fileUnreadable {
                        // Chosen again, the file can be read until the app quits.
                        Button {
                            OpenFilePanel.choose(in: error.url.deletingLastPathComponent(), multiple: false) { urls in
                                urls.first.map { page.load($0) }
                            }
                        } label: {
                            Text("Choose File…", comment: "Button of the page shown when a local file can't be read: opens the file panel")
                        }
                        .accessibilityIdentifier("pageLoadErrorChooseFileButton")
                    }
                    Button {
                        _ = page.retryFailedLoad()
                    } label: {
                        Text("Try Again", comment: "Button of the page shown after a page couldn't load: loads it again")
                    }
                    .accessibilityIdentifier("pageLoadErrorRetryButton")
                    if error.kind == .certificate, let trust = page.loadFailure.serverTrust {
                        Button {
                            CertificatePanel.showInvalid(trust, host: error.host, in: NSApp.keyWindow)
                        } label: {
                            Text(
                                "Show Certificate",
                                comment: "Button of the page shown after a certificate error: shows the website's certificate",
                            )
                        }
                        .accessibilityIdentifier("pageLoadErrorCertificateButton")
                    }
                }
                // Only if the user asks: in red, set apart; this certificate, this website, until the app quits.
                if page.loadFailure.canVisitAnyway {
                    Button {
                        page.visitDespiteInvalidCertificate()
                    } label: {
                        Text(
                            "Visit This Website Anyway",
                            comment: "Red button of the page shown after a certificate error: opens the website despite the risk",
                        )
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .accessibilityIdentifier("pageLoadErrorVisitAnywayButton")
                }
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { activate() })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pageLoadError")
    }

    private var symbolName: String {
        switch error.kind {
        case .offline: "wifi.slash"
        case .certificate: "lock.trianglebadge.exclamationmark"
        case .loginRequired: "person.badge.key"
        case .fileUnreadable: "doc.badge.ellipsis"
        default: "exclamationmark.triangle"
        }
    }

    private var title: Text {
        switch error.kind {
        case .offline:
            Text("You Aren't Connected to the Internet", comment: "Title of the page shown when the Mac is offline")
        case .certificate:
            Text("This Connection Isn't Private", comment: "Title of the page shown when a website's certificate isn't valid")
        case .fileUnreadable:
            Text("Matcha Can't Open This File", comment: "Title of the page shown when a local file can't be read")
        default:
            Text("Matcha Can't Open This Page", comment: "Title of the page shown after a page couldn't load")
        }
    }

    private var description: Text {
        let host = error.host
        return switch error.kind {
        case .offline:
            Text(
                "This page can't be shown until your Mac is connected to the internet.",
                comment: "Page shown when the Mac is offline",
            )
        case .serverNotFound:
            Text("Matcha can't find the server “\(host)”.", comment: "Page shown when a website's name leads nowhere; %@ is the website")
        case .timedOut:
            Text("The server “\(host)” took too long to respond.", comment: "Page shown after a timeout; %@ is the website")
        case .cannotConnect:
            Text(
                "Matcha can't connect to the server “\(host)”.",
                comment: "Page shown when a server refuses the connection; %@ is the website",
            )
        case .certificate:
            Text(
                "The certificate of “\(host)” isn't valid. Someone may be impersonating this website to steal your information.",
                comment: "Page shown after a certificate error; %@ is the website",
            )
        case .loginRequired:
            Text("“\(host)” needs a user name and password.", comment: "Page shown when a website's login was cancelled; %@ is the website")
        case .fileUnreadable:
            Text(
                """
                “\(error.url.lastPathComponent)” was moved, or Matcha can no longer read it since it was reopened. Choose it \
                again to open it.
                """,
                comment: "Page shown when a local file can't be read; %@ is the file's name",
            )
        case .other:
            Text(verbatim: error.detail)
        }
    }
}
