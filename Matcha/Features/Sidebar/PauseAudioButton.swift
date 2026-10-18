import SwiftUI

/// Icône haut-parleur d'un onglet qui joue du son (tâche 5.10) : un clic met en pause tous les médias de sa page, sans
/// sélectionner l'onglet ; l'icône disparaît quand la pause est faite. Sur une ligne d'onglet (`row`), un morceau de split
/// (`segment`, plus petit) ou en pastille sur une tuile de favori (`badge`).
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
    /// Pour VoiceOver, sur une ligne, un morceau de split ou une tuile dont les boutons sont masqués : « Lecture audio »
    /// en valeur et l'action « Mettre le son en pause » pendant que `tab` joue du son.
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

    /// En Debug, un onglet en veille (tâche 5.6) vaut « suspended » pour les tests d'interface.
    private var value: Text {
        #if DEBUG
            if tab.suspension.isSuspended {
                return Text(verbatim: "suspended")
            }
        #endif
        return tab.isPlayingAudio ? Text("Playing Audio", comment: "Accessibility value of a tab that plays sound") : Text(verbatim: "")
    }
}
