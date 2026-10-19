import Accessibility
import Foundation

/// VoiceOver announcement of the page zoom (task 5.4) after ⌘+, ⌘-, ⌘0 or a click on the zoom badge: “Page zoom:
/// 125%”. The address bar badge changes without VoiceOver moving to it: without an announcement, the change would
/// go unnoticed.
enum ZoomAnnouncement {
    nonisolated static func text(for level: Double) -> String {
        String(
            localized: "Page zoom: \(ZoomLevels.percentText(level))",
            comment: "VoiceOver announcement after ⌘+, ⌘- or ⌘0, or a click on the zoom badge; the argument is a percentage",
        )
    }

    /// High priority: VoiceOver also reads the menu closing or keyboard focus moving to the page, which would cut
    /// off an announcement of normal priority.
    static func post(_ level: Double) {
        var announcement = AttributedString(text(for: level))
        announcement.accessibilitySpeechAnnouncementPriority = .high
        AccessibilityNotification.Announcement(announcement).post()
    }
}
