import SwiftUI
import WebKit

/// Couche de l'aperçu sur les pages affichées (tous les panneaux d'un split) : voile sur chaque page, barre
/// (adresse, « Ouvrir en onglet », ×) et panneau à 85 % de la zone des pages. Les barres d'adresse au-dessus des
/// pages, la barre latérale et les intervalles restent hors du voile. Un clic de la fenêtre hors du panneau et
/// de sa barre ferme l'aperçu ; sur le voile, il s'arrête là. Le panneau grandit depuis le lien cliqué ; il
/// disparaît sans animation, pour qu'aucun panneau vide ne reste à l'écran quand la page passe dans la carte.
struct PeekOverlay: View {
    static let opening = Animation.spring(duration: 0.32, bounce: 0.1)
    static let reducedOpening = Animation.easeOut(duration: 0.15)
    static let initialScale = 0.5

    let tabManager: TabManager
    /// Pages des panneaux affichés, dans le repère de la couche ; l'aperçu se place dans leur réunion.
    let pages: [CGRect]
    /// Coins de chaque page : ceux de la carte, droits en haut sous une barre d'adresse.
    let pageCorners: RectangleCornerRadii

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let area = pages.dropFirst().reduce(pages.first ?? .zero) { $0.union($1) }
        let layout = PeekLayout(container: area.size)
        ZStack(alignment: .topLeading) {
            if let peek = tabManager.peek, let webView = peek.tab.webView {
                scrim(in: area)
                panel(webView, of: peek, layout: layout, area: area.size)
                PeekToolbar(page: peek.tab, tabManager: tabManager)
                    .frame(width: layout.toolbar.width, height: layout.toolbar.height)
                    .position(x: layout.toolbar.midX, y: layout.toolbar.midY)
                    .transition(.asymmetric(insertion: .opacity, removal: .identity))
                outsideClickArea(layout)
            }
        }
        .frame(width: area.width, height: area.height)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Peek", comment: "Accessibility label of the floating preview opened by Shift-clicking a link"))
        .accessibilityIdentifier("peek")
        .accessibilityHidden(tabManager.peek == nil)
        // Ouverture animée ; fermeture et passage en onglet sans animation.
        .animation(openingAnimation, value: tabManager.peek?.id)
        .position(x: area.midX, y: area.midY)
    }

    private var openingAnimation: Animation? {
        guard tabManager.peek != nil else {
            return nil
        }
        return reduceMotion ? Self.reducedOpening : Self.opening
    }

    /// Voile sur chaque page : arrête les clics et le défilement destinés à la page dessous ; un clic dessus
    /// ferme l'aperçu.
    private func scrim(in area: CGRect) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(Array(pages.enumerated()), id: \.offset) { _, page in
                UnevenRoundedRectangle(cornerRadii: pageCorners)
                    .fill(Color.black.opacity(colorScheme == .dark ? 0.5 : 0.3))
                    .frame(width: page.width, height: page.height)
                    .position(x: page.midX - area.minX, y: page.midY - area.minY)
            }
        }
        .frame(width: area.width, height: area.height)
        .onTapGesture { PeekActions.close(in: tabManager) }
        .accessibilityHidden(true)
        .transition(.asymmetric(insertion: .opacity, removal: .identity))
    }

    private func panel(_ webView: WKWebView, of peek: Peek, layout: PeekLayout, area: CGSize) -> some View {
        VStack(spacing: 0) {
            // Recherche dans la page (tâche 5.3) et demandes de permission (tâche 5.2) de la page de l'aperçu.
            FindBar(page: peek.tab)
            PermissionBanner(prompts: peek.tab.permissionPrompts)
            PeekWebHost(webView: webView) { PeekActions.close(in: tabManager) }
        }
        .background(.background)
        .clipShape(.rect(cornerRadius: BrowserWindowView.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BrowserWindowView.cardCornerRadius)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        .frame(width: layout.pane.width, height: layout.pane.height)
        .position(x: layout.pane.midX, y: layout.pane.midY)
        // Toute la zone : le point d'ancrage de l'agrandissement s'y rapporte.
        .frame(width: area.width, height: area.height)
        // Un nouvel aperçu = un nouveau conteneur (la vue web n'y est ajoutée qu'à la création).
        .id(peek.id)
        .transition(.asymmetric(insertion: insertion(from: peek.openingPoint), removal: .identity))
    }

    private func insertion(from point: CGPoint) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: Self.initialScale, anchor: UnitPoint(x: point.x, y: point.y)).combined(with: .opacity)
    }

    /// Hors du panneau et de sa barre, un clic de la fenêtre ferme l'aperçu puis atteint sa cible.
    private func outsideClickArea(_ layout: PeekLayout) -> some View {
        let bounds = layout.pane.union(layout.toolbar)
        return Color.clear
            .frame(width: bounds.width, height: bounds.height)
            .background { OutsideClickMonitor { PeekActions.close(in: tabManager) } }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .position(x: bounds.midX, y: bounds.midY)
    }
}
