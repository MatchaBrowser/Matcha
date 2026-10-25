import SwiftUI

/// Layout of a page's banner (permission, link to another app): all on one line if the card is wide enough;
/// otherwise the text, then the buttons (in a column if needed). The buttons ignore clicks for half a second after the
/// banner appears: a click meant for the page, under the pointer, can't answer it (audit W9). VoiceOver says when it
/// appears (review IU20): its label, then the user reaches it.
struct PromptBannerLayout<Icon: View, Message: View, Buttons: View>: View {
    static var clickDelay: Duration {
        .milliseconds(500)
    }

    private let label: String
    private let identifier: String
    private let icon: Icon
    private let message: Message
    private let buttons: Buttons
    @State private var acceptsClicks = false

    init(
        label: String,
        identifier: String,
        @ViewBuilder icon: () -> Icon,
        @ViewBuilder message: () -> Message,
        @ViewBuilder buttons: () -> Buttons,
    ) {
        self.label = label
        self.identifier = identifier
        self.icon = icon()
        self.message = message()
        self.buttons = buttons()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) {
                icon
                message.fixedSize()
                Spacer(minLength: 12)
                HStack(spacing: 8) { guardedButtons }
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
                        guardedButtons
                    }
                    VStack(alignment: .trailing, spacing: 6) { guardedButtons }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(verbatim: label))
        .accessibilityIdentifier(identifier)
        .onAppear { AccessibilityNotification.Announcement(label).post() }
        .task {
            try? await Task.sleep(for: Self.clickDelay)
            acceptsClicks = true
        }
    }

    private var guardedButtons: some View {
        buttons.allowsHitTesting(acceptsClicks)
    }
}
