import Foundation

/// SF Symbol offered in an icon grid (`SymbolPickerGrid`), with its name read by VoiceOver and shown as a tooltip.
/// The folders' symbols all exist since macOS 11, the Spaces' since macOS 13 at the latest
/// (`name_availability.plist` of CoreGlyphs); a test checks that they exist. The same name is translated once for
/// both lists (same key, same comment).
nonisolated struct SymbolChoice: Identifiable, Sendable {
    let name: String
    let title: LocalizedStringResource

    var id: String {
        name
    }

    /// Icons offered for a pinned folder; “folder”, first, is the default icon.
    static let folderIcons = [
        SymbolChoice(name: "folder", title: LocalizedStringResource("Folder", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "folder.fill", title: LocalizedStringResource("Filled Folder", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "star", title: LocalizedStringResource("Star", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "heart", title: LocalizedStringResource("Heart", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "house", title: LocalizedStringResource("House", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "briefcase", title: LocalizedStringResource("Briefcase", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "book", title: LocalizedStringResource("Book", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "graduationcap", title: LocalizedStringResource("Graduation Cap", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "cart", title: LocalizedStringResource("Shopping Cart", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "bag", title: LocalizedStringResource("Shopping Bag", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "creditcard", title: LocalizedStringResource("Credit Card", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "gamecontroller", title: LocalizedStringResource("Game Controller", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "music.note", title: LocalizedStringResource("Music", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "film", title: LocalizedStringResource("Film", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "photo", title: LocalizedStringResource("Photo", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "camera", title: LocalizedStringResource(
            "Camera Icon",
            defaultValue: "Camera",
            comment: "Icon choice (SF Symbol): a photo camera. Distinct from the Camera website permission.",
        )),
        SymbolChoice(name: "paintbrush", title: LocalizedStringResource("Paintbrush", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "hammer", title: LocalizedStringResource("Hammer", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(
            name: "wrench.and.screwdriver",
            title: LocalizedStringResource("Tools", comment: "Icon choice (SF Symbol): a wrench and a screwdriver"),
        ),
        SymbolChoice(name: "laptopcomputer", title: LocalizedStringResource("Laptop", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "terminal", title: LocalizedStringResource("Terminal", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "globe", title: LocalizedStringResource("Globe", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "airplane", title: LocalizedStringResource("Airplane", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "car", title: LocalizedStringResource("Car", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "leaf", title: LocalizedStringResource("Leaf", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "flame", title: LocalizedStringResource("Flame", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "bolt", title: LocalizedStringResource("Lightning Bolt", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "sparkles", title: LocalizedStringResource("Sparkles", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "flag", title: LocalizedStringResource("Flag", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "bookmark", title: LocalizedStringResource("Bookmark", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "tray", title: LocalizedStringResource("Tray", comment: "Icon choice (SF Symbol): an inbox tray")),
        SymbolChoice(name: "doc.text", title: LocalizedStringResource("Document", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "chart.bar", title: LocalizedStringResource("Chart", comment: "Icon choice (SF Symbol): a bar chart")),
        SymbolChoice(name: "person.2", title: LocalizedStringResource("People", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(
            name: "bubble.left.and.bubble.right",
            title: LocalizedStringResource("Conversation", comment: "Icon choice (SF Symbol): two speech bubbles"),
        ),
    ]
}
