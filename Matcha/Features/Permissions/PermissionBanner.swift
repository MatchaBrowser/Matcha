import SwiftUI

/// Bandeau des demandes de permission d'une page (tâche 5.2), en haut de sa carte (ou de l'aperçu, ou de la page
/// d'une mini-fenêtre) : il descend et pousse la page, sans la couvrir. Une demande à la fois : le site, ce qu'il
/// demande, et « Refuser », « Autoriser une fois », « Toujours autoriser ». Rien ne répond à la place de l'utilisateur.
struct PermissionBanner: View {
    let prompts: PermissionPromptQueue

    var body: some View {
        VStack(spacing: 0) {
            if let request = prompts.current {
                PermissionBannerContent(request: request) { prompts.answer($0) }
                    .id(request.id)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }
        }
        .clipped()
        .animation(.easeOut(duration: 0.2), value: prompts.current?.id)
    }
}

private struct PermissionBannerContent: View {
    let request: SitePermissionRequest
    let answer: (SitePermissionAnswer) -> Void

    var body: some View {
        // Tout sur une ligne si la carte est assez large ; sinon le texte, puis les boutons (en colonne au besoin).
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                icon
                message.fixedSize()
                Spacer(minLength: 12)
                HStack(spacing: 8) { buttons }
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 12) {
                    icon
                    message
                    Spacer(minLength: 0)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        Spacer(minLength: 0)
                        buttons
                    }
                    VStack(alignment: .trailing, spacing: 6) { buttons }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(
            "Permission Request",
            comment: "Accessibility label of the banner where a website asks to use the camera or microphone",
        ))
        .accessibilityIdentifier("permissionBanner")
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

    /// « meet.google.com souhaite utiliser votre caméra et votre micro. » : ne nomme que ce qui est demandé.
    private var prompt: Text {
        let site = request.origin.map { Text(verbatim: $0.displayName).bold() }
            ?? Text("This page", comment: "Permission banner: the page asking, when it has no website name (local file)")
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
