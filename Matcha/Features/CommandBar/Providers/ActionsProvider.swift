import Foundation

/// Command bar actions offered in the current state of the window, in the order of `CommandActionID.allCases`. The
/// text is ignored: the ranking does the matching.
@MainActor
final class ActionsProvider: CommandProvider {
    private let windowModel: WindowModel

    init(windowModel: WindowModel) {
        self.windowModel = windowModel
    }

    func candidates(for _: CommandQuery, context: CommandContext) async -> [CommandCandidate] {
        available(in: context)
    }

    /// Actions offered; also read right away for the rows of an unmodified ⌘L.
    func available(in context: CommandContext) -> [CommandCandidate] {
        CommandActionID.allCases.filter { isOffered($0, in: context) }.map { action in
            CommandCandidate(kind: .action(action, keywords: action.keywords), title: action.title, url: nil)
        }
    }

    private func isOffered(_ action: CommandActionID, in context: CommandContext) -> Bool {
        switch action {
        case .newSpace:
            // A private window has only one Space.
            !context.isPrivate
        case .copyURL:
            windowModel.selectedTab?.displayedURL != nil
        case .settings:
            true
        }
    }
}
