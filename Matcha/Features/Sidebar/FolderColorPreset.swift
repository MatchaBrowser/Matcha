import Foundation

/// Color of a folder's swatches (text and background): Apple's system colors, in exact 8-bit sRGB (they are
/// identical after a round trip through the database, `ThemeColor.hexString`).
nonisolated struct FolderColorPreset: Identifiable, Sendable {
    /// Stable identifier (UI tests), never displayed.
    let id: String
    let color: ThemeColor
    let title: LocalizedStringResource

    static let all = [
        FolderColorPreset("red", 0xFF3B30, LocalizedStringResource("Red", comment: "Folder color swatch")),
        FolderColorPreset("orange", 0xFF9500, LocalizedStringResource("Orange", comment: "Folder color swatch")),
        FolderColorPreset("yellow", 0xFFCC00, LocalizedStringResource("Yellow", comment: "Folder color swatch")),
        FolderColorPreset("green", 0x34C759, LocalizedStringResource("Green", comment: "Folder color swatch")),
        FolderColorPreset("turquoise", 0x30B0C7, LocalizedStringResource("Turquoise", comment: "Folder color swatch")),
        FolderColorPreset("blue", 0x007AFF, LocalizedStringResource("Blue", comment: "Folder color swatch")),
        FolderColorPreset("indigo", 0x5856D6, LocalizedStringResource("Indigo", comment: "Folder color swatch")),
        FolderColorPreset("purple", 0xAF52DE, LocalizedStringResource("Purple", comment: "Folder color swatch")),
        FolderColorPreset("pink", 0xFF2D55, LocalizedStringResource("Pink", comment: "Folder color swatch")),
        FolderColorPreset("gray", 0x8E8E93, LocalizedStringResource("Gray", comment: "Folder color swatch")),
    ]

    private init(_ id: String, _ rgb: UInt32, _ title: LocalizedStringResource) {
        self.id = id
        color = ThemeColor(rgb: rgb)
        self.title = title
    }
}
