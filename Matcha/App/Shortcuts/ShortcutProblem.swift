import Foundation
import Observation
import SwiftUI

/// Why a shortcut can't go to a command (Settings > Shortcuts).
nonisolated enum ShortcutProblem: Equatable, Sendable {
    /// Neither ⌘ nor ⌃ (nor a function key).
    case needsCommandOrControl
    /// Another command of the list has it.
    case usedBy(MenuShortcut)
    /// A command that keeps its shortcut (`MenuShortcut.fixedKeys`).
    case usedByMatcha
    /// A shortcut of macOS (Mission Control, Spotlight…).
    case usedByMacOS
    /// The mini window's global shortcut.
    case usedByMiniWindowShortcut
}
