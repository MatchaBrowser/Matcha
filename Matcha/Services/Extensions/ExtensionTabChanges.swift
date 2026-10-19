import Foundation

/// Properties of a tab that changed (pure equivalent of `WKWebExtension.TabChangedProperties`).
nonisolated struct ExtensionTabChanges: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let loading = ExtensionTabChanges(rawValue: 1 << 0)
    static let pinned = ExtensionTabChanges(rawValue: 1 << 1)
    static let playingAudio = ExtensionTabChanges(rawValue: 1 << 2)
    static let title = ExtensionTabChanges(rawValue: 1 << 3)
    static let url = ExtensionTabChanges(rawValue: 1 << 4)
    static let zoomFactor = ExtensionTabChanges(rawValue: 1 << 5)

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// What differs from `old` to `new`.
    init(from old: ExtensionBrowserState.Tab, to new: ExtensionBrowserState.Tab) {
        var changes: ExtensionTabChanges = []
        if old.isLoading != new.isLoading {
            changes.insert(.loading)
        }
        if old.isPinned != new.isPinned {
            changes.insert(.pinned)
        }
        if old.isPlayingAudio != new.isPlayingAudio {
            changes.insert(.playingAudio)
        }
        if old.title != new.title {
            changes.insert(.title)
        }
        if old.url != new.url {
            changes.insert(.url)
        }
        if old.zoomFactor != new.zoomFactor {
            changes.insert(.zoomFactor)
        }
        self = changes
    }
}
