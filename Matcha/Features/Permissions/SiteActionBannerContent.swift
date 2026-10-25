import SwiftUI

/// Banner line of a website's request to do something: “zoom.us wants to open “Zoom”.” (audit W2) or “example.com wants
/// to download files.” (W7), then “Cancel” / “Don't Allow”, “Open” / “Allow” and, if the answer can be remembered,
/// “Always Open” / “Always Allow”. No keyboard shortcut: a key pressed for the page can't answer it.
struct SiteActionBannerContent: View {
    let request: SiteActionRequest
    let answer: (SiteActionAnswer) -> Void

    var body: some View {
        PromptBannerLayout(label: label, identifier: "siteActionBanner") {
            icon
        } message: {
            prompt
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("siteActionMessage")
        } buttons: {
            Button {
                answer(.decline)
            } label: {
                declineTitle
            }
            .accessibilityIdentifier("siteActionDeclineButton")
            Button {
                answer(.allowOnce)
            } label: {
                allowTitle
            }
            .accessibilityIdentifier("siteActionAllowOnceButton")
            if request.canRemember {
                Button {
                    answer(.alwaysAllow)
                } label: {
                    alwaysTitle
                }
                .accessibilityIdentifier("siteActionAlwaysAllowButton")
            }
        }
    }

    @ViewBuilder private var icon: some View {
        if let appIcon = request.appIcon {
            Image(nsImage: appIcon)
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
        } else {
            Image(systemName: request.action.symbolName)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private var site: Text {
        request.origin.map { Text(verbatim: $0.displayName).bold() }
            ?? Text("This page", comment: "Permission banner: the page asking, when it has no website name (local file)")
    }

    private var label: String {
        switch request.action {
        case .openApp:
            String(
                localized: "Request to Open an App",
                comment: "Accessibility label of the banner where a website asks to open another app",
            )
        case .downloadFiles:
            String(localized: "Download Request", comment: "Accessibility label of the banner where a website asks to download files")
        }
    }

    private var prompt: Text {
        switch request.action {
        case .openApp:
            let app = Text(verbatim: request.appName ?? "").bold()
            return Text(
                "\(site) wants to open \(app).",
                comment: "Banner: a website asks to open another app; the first %@ is the website, the second the app",
            )
        case .downloadFiles:
            return Text(
                "\(site) wants to download files.",
                comment: "Banner: a website wants to download files without a click; %@ is the website",
            )
        }
    }

    private var declineTitle: Text {
        switch request.action {
        case .openApp:
            Text("Cancel")
        case .downloadFiles:
            Text("Don't Allow", comment: "Banner where a website wants to download files: refuse")
        }
    }

    private var allowTitle: Text {
        switch request.action {
        case .openApp:
            Text("Open", comment: "Banner where a website asks to open another app: open the link in that app")
        case .downloadFiles:
            Text("Allow", comment: "Banner where a website wants to download files: allow them for this page")
        }
    }

    private var alwaysTitle: Text {
        switch request.action {
        case .openApp:
            Text("Always Open", comment: "Banner where a website asks to open another app: open it, and from now on without asking")
        case .downloadFiles:
            Text("Always Allow", comment: "Banner where a website wants to download files: allow, and from now on without asking")
        }
    }
}
