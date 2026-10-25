import SwiftUI

/// Banner for a page's requests, at the top of its card (or of the peek, or of a mini window's page): it slides down
/// and pushes the page, without covering it. One request at a time: permissions first (task 5.2: the site, what it
/// asks for, and “Don't Allow”, “Allow Once”, “Always Allow”; for notifications, “Don't Allow” and “Allow”, both
/// remembered), then opening another app (audit W2). Nothing answers on the user's behalf.
struct PermissionBanner: View {
    let prompts: PermissionPromptQueue

    var body: some View {
        VStack(spacing: 0) {
            if let request = prompts.current {
                PermissionBannerContent(request: request) { prompts.answer($0) }
                    .id(request.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            } else if let request = prompts.currentAction {
                SiteActionBannerContent(request: request) { prompts.answerAction($0) }
                    .id(request.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }
        }
        .clipped()
        .motionAnimation(.easeOut(duration: 0.2), value: prompts.current?.id ?? prompts.currentAction?.id)
    }
}

private struct PermissionBannerContent: View {
    let request: SitePermissionRequest
    let answer: (SitePermissionAnswer) -> Void

    var body: some View {
        PromptBannerLayout(
            label: String(
                localized: "Permission Request",
                comment: "Accessibility label of the banner where a website asks for a permission (camera, microphone, notifications)",
            ),
            identifier: "permissionBanner",
        ) {
            icon
        } message: {
            message
        } buttons: {
            buttons
        }
    }

    private var icon: some View {
        HStack(spacing: 2) {
            ForEach(SitePermissionKind.allCases.filter(request.asked.contains)) { kind in
                Image(systemName: "\(kind.symbolName).fill")
            }
        }
        .font(.system(size: 14))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private var message: some View {
        VStack(alignment: .leading, spacing: 2) {
            prompt
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("permissionMessage")
            if let frameName = request.frameName {
                Text(
                    "Requested by an embedded frame from \(frameName).",
                    comment: "Permission banner: the request comes from a frame of another website inside the page; %@ is that website",
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Notifications are asked on their own (`Notification.requestPermission()`), never with the camera.
    private var isNotificationRequest: Bool {
        request.asked.contains(.notifications)
    }

    /// “meet.google.com wants to use your camera and microphone.”: names only what is requested.
    private var prompt: Text {
        let site = request.origin.map { Text(verbatim: $0.displayName).bold() }
            ?? Text("This page", comment: "Permission banner: the page asking, when it has no website name (local file)")
        if isNotificationRequest {
            return Text("\(site) wants to send you notifications.", comment: "Permission banner; %@ is the website")
        }
        switch (request.asked.contains(.camera), request.asked.contains(.microphone)) {
        case (true, true):
            return Text("\(site) wants to use your camera and microphone.", comment: "Permission banner; %@ is the website")
        case (true, false):
            return Text("\(site) wants to use your camera.", comment: "Permission banner; %@ is the website")
        default:
            return Text("\(site) wants to use your microphone.", comment: "Permission banner; %@ is the website")
        }
    }

    @ViewBuilder private var buttons: some View {
        Button {
            answer(.deny)
        } label: {
            Text("Don't Allow", comment: "Permission banner: refuse, and remember it for this website")
        }
        .accessibilityIdentifier("permissionDenyButton")
        if isNotificationRequest {
            // Always remembered: allowed for this page only, the website would lose it as soon as it is reloaded.
            Button {
                answer(.alwaysAllow)
            } label: {
                Text("Allow", comment: "Permission banner: allow the website to send notifications, and remember it")
            }
            .accessibilityIdentifier("permissionAlwaysAllowButton")
        } else {
            allowButtons
        }
    }

    @ViewBuilder private var allowButtons: some View {
        Button {
            answer(.allowOnce)
        } label: {
            Text("Allow Once", comment: "Permission banner: allow for this request only, nothing is remembered")
        }
        .accessibilityIdentifier("permissionAllowOnceButton")
        if request.canRemember {
            Button {
                answer(.alwaysAllow)
            } label: {
                Text("Always Allow", comment: "Permission banner: allow, and remember it for this website")
            }
            .accessibilityIdentifier("permissionAlwaysAllowButton")
        }
    }
}
