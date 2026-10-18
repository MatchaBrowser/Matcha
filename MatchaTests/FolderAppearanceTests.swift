import AppKit
import Foundation
@testable import Matcha
import Testing

struct FolderAppearanceTests {
    private let yellow = ThemeColor(rgb: 0xFFCC00)
    private let indigo = ThemeColor(rgb: 0x5856D6)

    @Test func `default appearance has no icon nor colors`() {
        let appearance = FolderAppearance()
        #expect(appearance.isDefault)
        #expect(appearance == .default)
        #expect(appearance.displayedTextColor == nil)
        #expect(appearance.summary == "default text:none background:none")
        #expect(!FolderAppearance(icon: .symbol("star")).isDefault)
    }

    @Test func `displayed text color is the chosen one, else readable on the background`() {
        #expect(FolderAppearance(textColor: indigo).displayedTextColor == indigo)
        #expect(FolderAppearance(textColor: indigo, backgroundColor: yellow).displayedTextColor == indigo)
        #expect(FolderAppearance(backgroundColor: yellow).displayedTextColor == .black)
        #expect(FolderAppearance(backgroundColor: indigo).displayedTextColor == .white)
    }

    @Test func `normalized appearance rounds colors to 8 bits and drops invalid icons`() {
        let picked = ThemeColor(red: 0.123_456, green: 0.5, blue: 0.987_654)
        let normalized = FolderAppearance(icon: .symbol("star"), textColor: picked).normalized
        #expect(normalized.icon == .symbol("star"))
        #expect(normalized.textColor?.hexString == "#1F80FC")
        #expect(normalized.textColor == ThemeColor(hexString: "#1F80FC"))
        #expect(normalized.normalized == normalized)
        #expect(FolderAppearance(icon: .emoji("ab")).normalized.icon == .default)
        #expect(FolderAppearance(icon: .emoji(" 🌿 ")).normalized.icon == .emoji("🌿"))
        #expect(FolderAppearance(icon: .symbol("Not A Symbol")).normalized.icon == .default)
        #expect(FolderAppearance(icon: .symbol("")).normalized.icon == .default)
    }

    @Test func `stored form round trips`() {
        let appearances = [
            FolderAppearance(),
            FolderAppearance(icon: .symbol("wrench.and.screwdriver"), textColor: indigo),
            FolderAppearance(icon: .emoji("👩🏽‍💻"), backgroundColor: yellow),
            FolderAppearance(icon: .emoji("🇫🇷"), textColor: .white, backgroundColor: .black),
        ]
        for appearance in appearances {
            let stored = FolderAppearance(
                storedIcon: appearance.storedIcon,
                textColorHex: appearance.storedTextColor,
                backgroundColorHex: appearance.storedBackgroundColor,
            )
            #expect(stored == appearance)
        }
        #expect(FolderAppearance(icon: .symbol("star")).storedIcon == "symbol:star")
        #expect(FolderAppearance(icon: .emoji("🌿")).storedIcon == "emoji:🌿")
        #expect(FolderAppearance().storedIcon == nil)
        #expect(FolderAppearance(icon: .emoji("🌿"), textColor: indigo).summary == "emoji:🌿 text:#5856D6 background:none")
    }

    /// Une base modifiée à la main, une synchro ou une version future : ce qui est illisible redevient la valeur par défaut.
    @Test(arguments: [nil, "", "star", "symbol:", "symbol:Star", "symbol:star fill", "emoji:", "emoji:ab", "emoji:😀😀", "other:x"])
    func `unreadable stored icons fall back to the default`(stored: String?) {
        #expect(SidebarIcon(storedValue: stored) == .default)
    }

    @Test func `hexadecimal colors`() {
        #expect(ThemeColor(hexString: "#FF3B30") == ThemeColor(rgb: 0xFF3B30))
        #expect(ThemeColor(hexString: "ff3b30") == ThemeColor(rgb: 0xFF3B30))
        #expect(ThemeColor(rgb: 0xFF3B30).hexString == "#FF3B30")
        #expect(ThemeColor(red: 0.5, green: 0, blue: 1).hexString == "#8000FF")
        #expect(ThemeColor(rgb: 0x000000) == .black)
        #expect(ThemeColor(rgb: 0xFFFFFF) == .white)
        for invalid in ["", "#", "#FFF", "#GG0000", "+12345", "#-12345", "#FF3B30FF", " #FF3B30"] {
            #expect(ThemeColor(hexString: invalid) == nil, "\(invalid)")
        }
    }

    @Test func `swatches survive the stored form exactly`() {
        #expect(FolderColorPreset.all.count == 10)
        #expect(Set(FolderColorPreset.all.map(\.id)).count == FolderColorPreset.all.count)
        for preset in FolderColorPreset.all {
            #expect(ThemeColor(hexString: preset.color.hexString) == preset.color, "\(preset.id)")
        }
    }

    @MainActor
    @Test func `every folder symbol exists on this macOS`() {
        let names = SymbolChoice.folderIcons.map(\.name)
        #expect(names.first == SidebarIcon.defaultFolderSymbol)
        #expect(names.count >= 30)
        #expect(Set(names).count == names.count)
        for name in names {
            #expect(NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil, "\(name)")
            #expect(SidebarIcon.isSymbolName(name), "\(name)")
        }
    }
}
