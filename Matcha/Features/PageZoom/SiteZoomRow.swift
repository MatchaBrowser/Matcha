import SwiftUI

/// “Zoom” row of the site settings (task 5.4): zoom out, the site's zoom (a click goes back to 100%), zoom in. It
/// shows the zoom remembered for the displayed tab's site and follows changes made with the keyboard; a change
/// spreads to all open pages of the site.
struct SiteZoomRow: View {
    let tab: BrowserTab
    /// Per-site zoom of the window; nil: that of the page alone.
    let siteZooms: SiteZoomStore?

    private var site: String? {
        SiteZoomKey.key(for: tab.documentURL)
    }

    /// Zoom of the site (it may differ briefly from the page's, while the page loads its document).
    private var level: Double {
        if let siteZooms, let site {
            return siteZooms.level(forSite: site)
        }
        return tab.pageZoom
    }

    var body: some View {
        let level = level
        HStack(spacing: 8) {
            Label {
                Text("Zoom", comment: "Site settings: zoom of the pages of the website")
            } icon: {
                Image(systemName: "plus.magnifyingglass")
            }
            .lineLimit(1)
            Spacer(minLength: 8)
            // Three separate buttons rather than a `ControlGroup`, which would make them segments of a single
            // control: each keeps its state, its help tag and its identifier.
            HStack(spacing: 4) {
                Button { apply(.zoomOut, from: level) } label: {
                    Label { Text("Zoom Out") } icon: { Image(systemName: "minus") }
                }
                .help(Text("Zoom Out"))
                .disabled(ZoomLevels.Change.zoomOut.level(from: level) == nil)
                .accessibilityIdentifier("siteZoomOutButton")
                Button { apply(.actualSize, from: level) } label: {
                    Text(verbatim: ZoomLevels.percentText(level))
                        .monospacedDigit()
                        .frame(minWidth: 40)
                }
                .help(Text("Actual Size"))
                .disabled(ZoomLevels.isActualSize(level))
                .accessibilityLabel(Text("Actual Size"))
                .accessibilityValue(Text(verbatim: ZoomLevels.percentText(level)))
                .accessibilityIdentifier("siteZoomResetButton")
                Button { apply(.zoomIn, from: level) } label: {
                    Label { Text("Zoom In") } icon: { Image(systemName: "plus") }
                }
                .help(Text("Zoom In"))
                .disabled(ZoomLevels.Change.zoomIn.level(from: level) == nil)
                .accessibilityIdentifier("siteZoomInButton")
            }
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .fixedSize()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("siteZoomRow")
    }

    private func apply(_ change: ZoomLevels.Change, from level: Double) {
        guard let next = change.level(from: level) else {
            return
        }
        if let siteZooms, let site {
            siteZooms.setLevel(next, forSite: site)
        } else {
            tab.setPageZoom(next)
        }
    }
}
