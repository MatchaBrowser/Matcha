import SwiftUI

/// Speaker icon of a tab that plays sound (task 5.10): a click pauses all the media of its page, without selecting
/// the tab; the icon disappears once paused. On a tab row (`row`), a split segment (`segment`, smaller) or as a
/// badge on a favorite tile (`badge`).
struct PauseAudioButton: View {
    enum Style {
        case row
        case segment
        case badge
    }

    let tab: BrowserTab
    var style = Style.row

    var body: some View {
        switch style {
        case .row:
            button
                .buttonStyle(SidebarIconButtonStyle())
                .scaleEffect(0.85)
        case .segment:
            button
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        case .badge:
            button
                .buttonStyle(.plain)
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .background(Circle().fill(.background))
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.12)))
                .contentShape(Circle())
        }
    }

    private var button: some View {
        Button("Pause Audio", systemImage: "speaker.wave.2.fill") { tab.pauseAudio() }
            .labelStyle(.iconOnly)
            .help("Pause Audio")
    }
}

extension View {
    /// For VoiceOver, on a row, a split segment or a tile whose buttons are hidden: “Playing Audio” as the value and
    /// the “Pause Audio” action while `tab` plays sound.
    func tabAudioAccessibility(_ tab: BrowserTab) -> some View {
        modifier(TabAudioAccessibility(tab: tab))
    }
}

private struct TabAudioAccessibility: ViewModifier {
    let tab: BrowserTab

    func body(content: Content) -> some View {
        content
            .accessibilityValue(value)
            .accessibilityActions {
                if tab.isPlayingAudio {
                    Button("Pause Audio") { tab.pauseAudio() }
                }
            }
    }

    /// In Debug, a sleeping tab (task 5.6) is worth “suspended” for the UI tests.
    private var value: Text {
        #if DEBUG
            if tab.suspension.isSuspended {
                return Text(verbatim: "suspended")
            }
        #endif
        return tab.isPlayingAudio ? Text("Playing Audio", comment: "Accessibility value of a tab that plays sound") : Text(verbatim: "")
    }
}
