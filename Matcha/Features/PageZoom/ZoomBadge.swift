import SwiftUI

/// Page zoom next to the address pill (task 5.4), as in Safari: “125%”, visible only away from 100%. It follows
/// each ⌘+, ⌘-, ⌘0 (rolling digits, small pulse), fades in and out; a click brings the page's site back to 100%,
/// like ⌘0. It sits next to the pill and not inside it: a button inside the pill's button would not receive its
/// clicks. It never takes keyboard focus.
struct ZoomBadge: View {
    /// Badge background: subtle in an address bar, material on the peek's floating bar.
    enum Style {
        case inline
        case floating
    }

    /// Described page: displayed tab, page of the peek or of the mini window.
    let page: BrowserTab?
    /// Per-site zoom of the window; nil: only the page goes back to 100%.
    let siteZooms: SiteZoomStore?
    var style = Style.inline

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// True if the zoom of `page` is not 100%.
    static func isShown(for page: BrowserTab?) -> Bool {
        page.map { !ZoomLevels.isActualSize($0.pageZoom) } ?? false
    }

    /// Animation of the badge and of the bar that holds it.
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : .snappy(duration: 0.25)
    }

    /// Click: the site of `page` goes back to 100% (all its open pages), like ⌘0, and VoiceOver announces it.
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
            // Small pulse at each change (none with Reduce Motion).
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
    /// Animates the bar holding the zoom badge of `page` at each change: the badge fades in or out while the
    /// address pill moves aside, instead of jumping.
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

/// Badge capsule, more pronounced on hover, dimmed during the click.
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
            .font((style == .floating ? Font.callout : .subheadline).weight(.semibold))
            .monospacedDigit()
            .lineLimit(1)
            .padding(.horizontal, style == .floating ? 10 : 7)
            .frame(height: style == .floating ? PeekLayout.toolbarHeight : 20)
            .background { background }
            .opacity(configuration.isPressed ? 0.6 : 1)
            // Click area taller than the capsule, in an address bar.
            .padding(.vertical, style == .floating ? 0 : 4)
            .contentShape(.rect)
            .onHover { isHovered = $0 }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .inline:
            Capsule().fill(Color.primary.opacity(isHovered ? 0.14 : 0.08))
        case .floating:
            // Like the address in the peek's bar, readable on the scrim.
            ZStack {
                Capsule().fill(.regularMaterial)
                Capsule().fill(Color.primary.opacity(isHovered ? 0.1 : 0))
            }
            .overlay { Capsule().strokeBorder(.hairline, lineWidth: 1) }
        }
    }
}
