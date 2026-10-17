import Accessibility
import Foundation

/// Annonce VoiceOver du zoom de la page (tâche 5.4) après ⌘+, ⌘-, ⌘0 ou un clic sur le badge du zoom : « Zoom de la
/// page : 125 % ». Le badge de la barre d'adresse change sans que VoiceOver s'y déplace : sans annonce, le changement
/// passerait inaperçu.
enum ZoomAnnouncement {
    nonisolated static func text(for level: Double) -> String {
        String(
            localized: "Page zoom: \(ZoomLevels.percentText(level))",
            comment: "VoiceOver announcement after ⌘+, ⌘- or ⌘0, or a click on the zoom badge; the argument is a percentage",
        )
    }

    /// Priorité haute : VoiceOver lit aussi la fermeture du menu ou le passage du clavier à la page, qui couperaient
    /// une annonce de priorité normale.
    static func post(_ level: Double) {
        var announcement = AttributedString(text(for: level))
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }
}
