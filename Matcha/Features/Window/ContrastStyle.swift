import SwiftUI

/// Translucent lines and fills of the interface, stronger with “Increase contrast” (System Settings > Accessibility >
/// Display, audit H3): macOS adapts its own colors, not these opacities.
struct ContrastStyle: ShapeStyle {
    let color: Color
    let opacity: Double
    let increasedOpacity: Double

    func resolve(in environment: EnvironmentValues) -> some ShapeStyle {
        color.opacity(environment.colorSchemeContrast == .increased ? increasedOpacity : opacity)
    }
}

extension ShapeStyle where Self == ContrastStyle {
    /// Thin border of a card, a panel or a button.
    static var hairline: ContrastStyle {
        ContrastStyle(color: .primary, opacity: 0.12, increasedOpacity: 0.5)
    }

    /// Separator line.
    static var separatorLine: ContrastStyle {
        ContrastStyle(color: .primary, opacity: 0.15, increasedOpacity: 0.55)
    }

    /// Light background of a hovered row or a control.
    static var subtleFill: ContrastStyle {
        ContrastStyle(color: .primary, opacity: 0.07, increasedOpacity: 0.2)
    }
}
