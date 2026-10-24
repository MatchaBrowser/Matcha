import SwiftUI
import WebKit

/// Peek layer over the displayed pages (all panes of a split): scrim over each page, bar (address, “Open as Tab”,
/// ×) and panel at 85% of the pages area. The address bars above the pages, the sidebar and the gaps stay outside
/// the scrim. A click in the window outside the panel and its bar closes the peek; on the scrim, it stops there.
/// The panel grows from the clicked link; it disappears without animation, so that no empty panel stays on screen
/// when the page moves into the card.
struct PeekOverlay: View {
    static let opening = Animation.spring(duration: 0.32, bounce: 0.1)
    static let reducedOpening = Animation.easeOut(duration: 0.15)
    static let initialScale = 0.5

    let tabManager: TabManager
    /// This window's selection: the peek shows in the window that shows its source tab.
    let viewer: TabViewer
    /// Pages of the displayed panes, in the layer's coordinate space; the peek is placed in their union.
    let pages: [CGRect]
    /// Corners of each page: those of the card, square at the top under an address bar.
    let pageCorners: RectangleCornerRadii

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let area = pages.dropFirst().reduce(pages.first ?? .zero) { $0.union($1) }
        let layout = PeekLayout(container: area.size)
        ZStack(alignment: .topLeading) {
            if let peek, let webView = peek.tab.webView {
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
        .accessibilityHidden(peek == nil)
        // Animated opening; closing and turning into a tab without animation.
        .animation(openingAnimation, value: peek?.id)
        .position(x: area.midX, y: area.midY)
    }

    /// The Space's peek, if this window shows it.
    private var peek: Peek? {
        tabManager.peek(in: viewer)
    }

    private var openingAnimation: Animation? {
        guard peek != nil else {
            return nil
        }
        return reduceMotion ? Self.reducedOpening : Self.opening
    }

    /// Scrim over each page: stops the clicks and scrolling meant for the page below; a click on it closes the
    /// peek.
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
            // Find in page (task 5.3) and permission requests (task 5.2) of the peek's page.
            FindBar(page: peek.tab)
            PermissionBanner(prompts: peek.tab.permissionPrompts)
            PeekWebHost(webView: webView) { PeekActions.close(in: tabManager) }
                // Page crashed several times in a row (task 5.7): the message, until reload.
                .overlay {
                    if peek.tab.crash.isShowingProblem {
                        PageProblemView(page: peek.tab)
                    } else if let error = peek.tab.loadFailure.error {
                        PageLoadErrorView(page: peek.tab, error: error)
                    }
                }
        }
        .background(.background)
        .clipShape(.rect(cornerRadius: BrowserWindowView.cardCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: BrowserWindowView.cardCornerRadius)
                .strokeBorder(.hairline, lineWidth: 1)
                .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.35), radius: 30, y: 12)
        .frame(width: layout.pane.width, height: layout.pane.height)
        .position(x: layout.pane.midX, y: layout.pane.midY)
        // The whole area: the anchor point of the scaling refers to it.
        .frame(width: area.width, height: area.height)
        // A new peek = a new container (the web view is only added to it at creation).
        .id(peek.id)
        .transition(.asymmetric(insertion: insertion(from: peek.openingPoint), removal: .identity))
    }

    private func insertion(from point: CGPoint) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: Self.initialScale, anchor: UnitPoint(x: point.x, y: point.y)).combined(with: .opacity)
    }

    /// Outside the panel and its bar, a click in the window closes the peek then reaches its target.
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
