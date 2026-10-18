import SwiftUI

/// Un Space d'Arc dans l'aperçu de l'import (tâche 7.1) : son icône sur ses couleurs, son nom, ce qu'il contient et
/// son profil s'il n'est pas le principal.
struct ArcImportSpaceRow: View {
    let space: ArcSidebar.Space

    var body: some View {
        HStack(spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: space.name.isEmpty ? String(localized: "Untitled Space") : space.name)
                    .lineLimit(1)
                Text(verbatim: details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        let symbol = ArcAppearance.spaceSymbol(for: space.icon, symbolExists: SidebarIconView.symbolExists)
        let colors = ArcAppearance.theme(for: space.colors)?.colors.map(\.color)
        return SidebarIconView(
            icon: SidebarIcon(spaceSymbol: symbol ?? SidebarIcon.defaultSpaceSymbol),
            defaultSymbol: SidebarIcon.defaultSpaceSymbol,
            tint: colors == nil ? nil : .white,
            size: 13,
            emojiSize: 16,
        )
        .frame(width: 28, height: 28)
        .background {
            if let colors {
                Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            } else {
                Circle().fill(.quaternary)
            }
        }
        .accessibilityHidden(true)
    }

    /// « 12 pinned tabs · 3 folders · Profile 1 ».
    private var details: String {
        let tabs = ImportNode.tabCount(of: space.pinned)
        let folders = ImportNode.folderCount(of: space.pinned)
        var parts = [String(localized: "\(tabs) pinned tabs", comment: "Content of an Arc Space in the import preview")]
        if folders > 0 {
            parts.append(String(localized: "\(folders) folders", comment: "Content of an Arc Space in the import preview"))
        }
        if case let .custom(name) = space.profile {
            parts.append(name)
        }
        return parts.joined(separator: " · ")
    }
}
