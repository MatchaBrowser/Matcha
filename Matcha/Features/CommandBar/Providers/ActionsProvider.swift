import Foundation

/// Actions de la barre de commande offertes dans l'état actuel de la fenêtre, dans l'ordre de
/// `CommandActionID.allCases`. Le texte est ignoré : le classement fait la correspondance.
@MainActor
final class ActionsProvider: CommandProvider {
    private let windowModel: WindowModel

    init(windowModel: WindowModel) {
        self.windowModel = windowModel
    }

    func candidates(for _: CommandQuery, context: CommandContext) async -> [CommandCandidate] {
        available(in: context)
    }

    /// Actions offertes ; lu aussi tout de suite pour les lignes de ⌘L non modifié.
    func available(in context: CommandContext) -> [CommandCandidate] {
        CommandActionID.allCases.filter { isOffered($0, in: context) }.map { action in
            CommandCandidate(kind: .action(action, keywords: action.keywords), title: action.title, url: nil)
        }
    }

    private func isOffered(_ action: CommandActionID, in context: CommandContext) -> Bool {
        switch action {
        case .newSpace:
            // Une fenêtre privée n'a qu'un Space.
            !context.isPrivate
        case .copyURL:
            windowModel.space.tabManager.selectedTab?.url != nil
        case .settings:
            true
        }
    }
}
