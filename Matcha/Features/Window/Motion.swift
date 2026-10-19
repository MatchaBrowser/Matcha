import AppKit
import SwiftUI

/// Animations that follow “Reduce motion” (System Settings > Accessibility > Display, audit H3): what slides, grows or
/// moves changes at once. Plain fades (theme, confirmations) stay: they don't move anything.
@MainActor
enum Motion {
    static var isReduced: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// `animation`, or none when motion is reduced.
    static func animation(_ animation: Animation?, reduced: Bool = isReduced) -> Animation? {
        reduced ? nil : animation
    }
}

/// `withAnimation` that follows “Reduce motion”.
@MainActor
func withMotion<Result>(_ animation: Animation?, _ body: () throws -> Result) rethrows -> Result {
    try withAnimation(Motion.animation(animation), body)
}

/// `.animation(_:value:)` that follows “Reduce motion”.
private struct MotionAnimation<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation?
    let value: Value

    func body(content: Content) -> some View {
        content.animation(Motion.animation(animation, reduced: reduceMotion), value: value)
    }
}

extension View {
    /// See `MotionAnimation`.
    func motionAnimation(_ animation: Animation?, value: some Equatable) -> some View {
        modifier(MotionAnimation(animation: animation, value: value))
    }
}
