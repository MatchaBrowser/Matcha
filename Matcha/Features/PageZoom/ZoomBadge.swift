import SwiftUI

/// Zoom de la page à côté de la pastille d'adresse (tâche 5.4), comme dans Safari : « 125 % », visible seulement hors
/// de 100 %. Il suit chaque ⌘+, ⌘-, ⌘0 (chiffres qui défilent, petite pulsation), apparaît et disparaît en fondu ; un clic
/// ramène le site de la page à 100 %, comme ⌘0. Il est à côté de la pastille et non dedans : un bouton dans le bouton de
/// la pastille ne recevrait pas ses clics. Il ne prend jamais le clavier.
struct ZoomBadge: View {
    /// Fond du badge : discret dans une barre d'adresse, matériau sur la barre flottante de l'aperçu.
    enum Style {
        case inline
        case floating
    }

    /// Page décrite : onglet affiché, page de l'aperçu ou de la mini-fenêtre.
    let page: BrowserTab?
    /// Zoom par site de la fenêtre ; nil : seule la page revient à 100 %.
    let siteZooms: SiteZoomStore?
    var style = Style.inline

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Vrai si le zoom de `page` n'est pas 100 %.
    static func isShown(for page: BrowserTab?) -> Bool {
        page.map { !ZoomLevels.isActualSize($0.pageZoom) } ?? false
    }

    /// Animation du badge et de la barre qui le porte.
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25)
    }

    /// Clic : le site de `page` revient à 100 % (toutes ses pages ouvertes), comme ⌘0, et VoiceOver l'annonce.
    static func reset(_ page: BrowserTab, siteZooms: SiteZoomStore?) {
        if let level = PageZoom.apply(.actualSize, to: page, siteZooms: siteZooms) {
            ZoomAnnouncement.post(level)
        }
    }

    var body: some View {
        if let page, Self.isShown(for: page) {
            let level = page.pageZoom
            let text = ZoomLevels.percentText(level)
            Button { Self.reset(page, siteZooms: siteZooms) } label: {
                Text(verbatim: text)
                    .contentTransition(reduceMotion ? .opacity : .numericText(value: level))
                    .animation(Self.animation(reduceMotion: reduceMotion), value: level)
            }
            .buttonStyle(ZoomBadgeButtonStyle(style: style))
            // Petite pulsation à chaque changement (aucune avec Réduire les animations).
            .phaseAnimator([1.0, 1.12], trigger: reduceMotion ? nil : level) { content, scale in
                content.scaleEffect(scale)
            } animation: { scale in
                scale > 1 ? .easeOut(duration: 0.08) : .spring(duration: 0.3, bounce: 0.45)
            }
            .fixedSize()
            .focusable(false)
            .help(Text("Actual Size"))
            .accessibilityLabel(Text(
                "Page Zoom",
                comment: "Accessibility label of the zoom badge next to the address; its value is a percentage",
            ))
            .accessibilityValue(Text(verbatim: text))
            .accessibilityIdentifier("zoomBadge")
            .transition(.opacity)
        }
    }
}

extension View {
    /// Anime la barre qui porte le badge du zoom de `page` à chaque changement : le badge apparaît ou disparaît en
    /// fondu pendant que la pastille d'adresse s'écarte, au lieu de sauter.
    func animatesZoomBadge(of page: BrowserTab?) -> some View {
        modifier(ZoomBadgeAnimation(level: page?.pageZoom))
    }
}

private struct ZoomBadgeAnimation: ViewModifier {
    let level: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(ZoomBadge.animation(reduceMotion: reduceMotion), value: level)
    }
}

/// Capsule du badge, plus marquée au survol, atténuée pendant le clic.
private struct ZoomBadgeButtonStyle: ButtonStyle {
    let style: ZoomBadge.Style

    func makeBody(configuration: Configuration) -> some View {
        ZoomBadgeCapsule(configuration: configuration, style: style)
    }
}

private struct ZoomBadgeCapsule: View {
    let configuration: ButtonStyleConfiguration
    let style: ZoomBadge.Style

    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: style == .floating ? 12 : 11, weight: .semibold))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, style == .floating ? 10 : 7)
            .frame(height: style == .floating ? PeekLayout.toolbarHeight : 20)
            .background { background }
            .opacity(configuration.isPressed ? 0.6 : 1)
            // Zone de clic plus haute que la capsule, dans une barre d'adresse.
            .padding(.vertical, style == .floating ? 0 : 4)
            .contentShape(.rect)
            .onHover { isHovered = $0 }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .inline:
            Capsule().fill(Color.primary.opacity(isHovered ? 0.14 : 0.08))
        case .floating:
            // Comme l'adresse de la barre de l'aperçu, lisible sur le voile.
            ZStack {
                Capsule().fill(.regularMaterial)
                Capsule().fill(Color.primary.opacity(isHovered ? 0.1 : 0))
            }
            .overlay { Capsule().strokeBorder(Color.primary.opacity(0.12), lineWidth: 1) }
        }
    }
}
