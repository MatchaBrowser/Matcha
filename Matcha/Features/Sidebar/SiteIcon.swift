import SwiftUI

/// Icon of a site: its own, otherwise a pill with the domain's initial, otherwise a globe.
/// A dark, colorless icon on a dark background (or a light one on a light background) is placed on a
/// contrasting plate to stay visible.
struct SiteIcon: View {
    let favicon: Favicon?
    let host: String?
    var size = 16.0

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        if let favicon {
            icon(favicon)
        } else if let host, !host.isEmpty {
            RoundedRectangle(cornerRadius: size * 0.25)
                .fill(Color(hue: FaviconPlaceholder.hue(for: host), saturation: 0.5, brightness: 0.75))
                .overlay {
                    Text(FaviconPlaceholder.initial(for: host))
                        .font(.system(size: size * 0.62, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
                .frame(width: size, height: size)
        } else {
            Image(systemName: "globe")
                .font(.system(size: size * 0.85))
                .frame(width: size, height: size)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func icon(_ favicon: Favicon) -> some View {
        let image = Image(nsImage: favicon.image)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
        if let plate = plateColor(for: favicon.tone) {
            image
                .frame(width: size * 0.75, height: size * 0.75)
                .frame(width: size, height: size)
                .background(plate, in: .rect(cornerRadius: size * 0.25))
        } else {
            image
                .frame(width: size, height: size)
                .clipShape(.rect(cornerRadius: size * 0.2))
        }
    }

    /// Light plate under a dark icon in dark mode, dark plate under a light icon in light mode.
    private func plateColor(for tone: FaviconTone) -> Color? {
        switch (tone, colorScheme) {
        case (.dark, .dark): .white.opacity(0.9)
        case (.light, .light): .black.opacity(0.75)
        default: nil
        }
    }
}
