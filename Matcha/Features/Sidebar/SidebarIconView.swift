import AppKit
import SwiftUI

/// Icon of a pinned folder or of a Space (`SidebarIcon`): its emoji, which keeps its colors; its SF Symbol, tinted
/// with `tint` or the current style; otherwise `defaultSymbol` (also for a symbol this macOS does not know,
/// received from a more recent Mac).
struct SidebarIconView: View {
    let icon: SidebarIcon
    let defaultSymbol: String
    /// Color of the symbol; nil: the current foreground style.
    var tint: Color?
    var size = 13.0
    /// Size of an emoji; nil: `size`.
    var emojiSize: Double?
    var weight = Font.Weight.regular

    var body: some View {
        switch icon.displayed(defaultSymbol: defaultSymbol, symbolExists: Self.symbolExists) {
        case let .emoji(emoji):
            Text(verbatim: emoji)
                .font(.system(size: emojiSize ?? size))
        case let .symbol(name):
            symbol(name)
        case .default:
            symbol(defaultSymbol)
        }
    }

    @ViewBuilder private func symbol(_ name: String) -> some View {
        let image = Image(systemName: name)
            .font(.system(size: size, weight: weight))
        if let tint {
            image.foregroundStyle(tint)
        } else {
            image
        }
    }

    /// The icon as a single `Text` (the symbol is an image inside it): switching from a symbol to an emoji only
    /// changes the text, not the view's structure. For a Space's button: its open popover (the editor) is attached to
    /// its accessibility element, which SwiftUI recreates without it when the structure of its content changes;
    /// VoiceOver would lose it as soon as an emoji replaces the symbol.
    static func text(
        _ icon: SidebarIcon,
        defaultSymbol: String,
        tint: Color? = nil,
        size: Double = 13,
        emojiSize: Double? = nil,
        weight: Font.Weight = .regular,
    ) -> Text {
        switch icon.displayed(defaultSymbol: defaultSymbol, symbolExists: symbolExists) {
        case let .emoji(emoji):
            return Text(verbatim: emoji).font(.system(size: emojiSize ?? size))
        case let .symbol(name):
            let symbol = Text(Image(systemName: name)).font(.system(size: size, weight: weight))
            return tint.map { symbol.foregroundStyle($0) } ?? symbol
        case .default:
            return text(.symbol(defaultSymbol), defaultSymbol: defaultSymbol, tint: tint, size: size, weight: weight)
        }
    }

    /// True if this macOS knows the SF Symbol `name`.
    static func symbolExists(_ name: String) -> Bool {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}
