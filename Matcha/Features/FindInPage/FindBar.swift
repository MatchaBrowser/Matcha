import SwiftUI

/// Find-in-page bar (task 5.3), at the top of the page it targets (card, peek, mini window): below the address bar
/// if there is one, above the permissions banner. It slides down and pushes the page, without covering it.
/// Magnifying glass, field (“Not Found” at the end when the last search found nothing; the public API does not give
/// the number of matches), previous and next match, ×.
struct FindBar: View {
    /// Name of the bar, placeholder text and label of its field.
    static let title = LocalizedStringResource(
        "Find in Page",
        comment: "Find bar: placeholder of the search field, accessibility label of the bar and of its field",
    )

    let page: BrowserTab
    /// Makes the page's split pane active (click in the field, arrows); nil outside the card.
    var activate: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            if page.find.isPresented {
                FindBarContent(page: page, activate: activate)
                    .transition(.move(edge: .top).combined(with: .opacity))
                Divider()
            }
        }
        .clipped()
        .motionAnimation(.easeOut(duration: 0.15), value: page.find.isPresented)
    }
}

private struct FindBarContent: View {
    let page: BrowserTab
    let activate: (() -> Void)?

    private var session: FindSession {
        page.find
    }

    var body: some View {
        HStack(spacing: 4) {
            field
            Button {
                activate?()
                session.findPrevious()
            } label: {
                Label { previousTitle } icon: { Image(systemName: "chevron.up") }
            }
            .help(previousTitle)
            .disabled(!session.hasQuery)
            .accessibilityIdentifier("findPreviousButton")
            Button {
                activate?()
                session.findNext()
            } label: {
                Label { nextTitle } icon: { Image(systemName: "chevron.down") }
            }
            .help(nextTitle)
            .disabled(!session.hasQuery)
            .accessibilityIdentifier("findNextButton")
            Spacer(minLength: 0)
            Button {
                FindActions.close(page)
            } label: {
                Label { closeTitle } icon: { Image(systemName: "xmark") }
            }
            .help(closeTitle)
            .accessibilityIdentifier("findCloseButton")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(SidebarIconButtonStyle())
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(FindBar.title))
        .accessibilityIdentifier("findBar")
        // VoiceOver announces “Not Found”: the text alone is not read when it appears.
        .onChange(of: session.status) { _, status in
            if status == .notFound {
                AccessibilityNotification.Announcement(String(localized: notFoundTitle)).post()
            }
        }
    }

    /// Magnifying glass, field and result in a single rounded frame.
    private var field: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            FindTextField(
                session: session,
                pageID: page.id,
                text: session.query,
                focusRequest: session.focusRequest,
                onCommand: perform,
                onFocus: activate,
            )
            if session.status == .notFound, session.hasQuery {
                Text(notFoundTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                    .accessibilityIdentifier("findStatus")
            }
        }
        .padding(.horizontal, 7)
        .frame(minWidth: 90, maxWidth: 300)
        .frame(height: 24)
        // In a narrow card, the field takes priority over the free space.
        .layoutPriority(1)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.hairline, lineWidth: 1))
    }

    private func perform(_ command: FindKeyCommand) {
        switch command {
        case .next:
            session.findNext()
        case .previous:
            session.findPrevious()
        case .close:
            FindActions.close(page)
        }
    }

    private var notFoundTitle: LocalizedStringResource {
        LocalizedStringResource("Not Found", comment: "Find bar: the last search found nothing in the page")
    }

    private var previousTitle: Text {
        Text("Previous Match", comment: "Find bar: button that selects the previous match in the page (⇧⌘G)")
    }

    private var nextTitle: Text {
        Text("Next Match", comment: "Find bar: button that selects the next match in the page (⌘G)")
    }

    private var closeTitle: Text {
        Text("Close Find Bar", comment: "Find bar: help tag and accessibility label of the × button")
    }
}
