import Accessibility
import SwiftUI

/// Small “URL Copied” capsule at the bottom of the content card: fades in, stays 1.5 s, then fades out. It never
/// takes the keyboard or clicks; VoiceOver announces each copy.
struct CopyConfirmationView: View {
    /// Gap with the bottom of the card.
    static let bottomMargin = 16.0

    let model: CopyConfirmationModel

    var body: some View {
        ZStack {
            if model.isVisible {
                capsule
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.isVisible)
        .padding(.bottom, Self.bottomMargin)
        .allowsHitTesting(false)
        .onChange(of: model.presentationCount) {
            AccessibilityNotification.Announcement(Self.announcement).post()
        }
    }

    private var capsule: some View {
        HStack(spacing: 6) {
            Image(systemName: "link")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(Self.message)
                .font(.system(size: 13, weight: .medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            // Material like the command bar, but thicker: in dark mode on a light page, the regular material turns
            // medium gray and white text becomes hard to read.
            Capsule()
                .fill(.thickMaterial)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        }
        .overlay {
            Capsule()
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.message)
        .accessibilityIdentifier("copyConfirmation")
    }

    /// High priority: VoiceOver also reads the menu closing or the keyboard moving to the page, which would cut off
    /// a normal-priority announcement.
    private static var announcement: AttributedString {
        var announcement = AttributedString(message)
        announcement.accessibilitySpeechAnnouncementPriority = .high
        return announcement
    }

    private static var message: String {
        String(localized: "URL Copied", comment: "Confirmation shown at the bottom of the page after copying its address (⇧⌘C)")
    }
}
