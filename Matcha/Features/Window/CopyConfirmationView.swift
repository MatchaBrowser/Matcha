import Accessibility
import SwiftUI

/// Petite capsule « URL copiée » en bas de la carte de contenu : apparaît en fondu, reste 1,5 s puis
/// disparaît en fondu. Elle ne prend jamais le clavier ni les clics ; VoiceOver annonce chaque copie.
struct CopyConfirmationView: View {
    /// Écart avec le bas de la carte.
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
            // Matériau comme la barre de commande, en plus épais : en sombre sur une page claire, le
            // matériau normal tourne au gris moyen et le texte blanc devient peu lisible.
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

    /// Priorité haute : VoiceOver lit aussi la fermeture du menu ou le passage du clavier à la page,
    /// qui couperaient une annonce de priorité normale.
    private static var announcement: AttributedString {
        var announcement = AttributedString(message)
        announcement.accessibilitySpeechAnnouncementPriority = .high
        return announcement
    }

    private static var message: String {
        String(localized: "URL Copied", comment: "Confirmation shown at the bottom of the page after copying its address (⇧⌘C)")
    }
}
