import Foundation

/// Ce que le panneau de la barre de commande lit et modifie : la barre d'une fenêtre de navigation
/// (`CommandBarModel`) ou celle d'une mini-fenêtre (`MiniCommandBarModel`).
@MainActor
protocol CommandBarPanelModel: AnyObject {
    var isPresented: Bool { get }
    var text: String { get }
    var rows: [CommandRow] { get }
    var selectedRowID: CommandRow.ID? { get }
    var selectedRow: CommandRow? { get }
    /// Change à chaque demande d'ouverture : le champ reprend le clavier et sélectionne tout.
    var focusRequest: Int { get }
    /// Moteur de l'ouverture en cours (« Rechercher sur … »).
    var searchEngine: SearchEngine { get }
    /// Onglet dont l'adresse est modifiée (icône du champ) ; nil pour une saisie neuve.
    var editedTab: BrowserTab? { get }
    /// Icônes des lignes.
    var rowIcons: CommandRowIcons { get }
    func updateText(_ newText: String)
    func moveSelection(by delta: Int)
    func dismiss()
}

/// Ce dont une ligne a besoin pour son icône.
@MainActor
struct CommandRowIcons {
    let faviconService: FaviconService
    /// Onglet vivant d'une ligne d'onglet ; nil s'il n'existe plus (ou si la barre ne propose pas d'onglets).
    let tab: (TabReference) -> BrowserTab?
}

/// Place du panneau dans sa fenêtre.
nonisolated enum CommandBarPlacement: Equatable, Sendable {
    /// Fenêtre de navigation : centré, 640 pt au plus, haut à 18 % de la hauteur (52 pt au moins).
    case window
    /// Mini-fenêtre : toute la largeur moins 10 pt de chaque côté, `top` pt sous le haut de la fenêtre.
    case belowToolbar(top: Double)

    func top(inHeight height: Double) -> Double {
        switch self {
        case .window: max(52, (height * 0.18).rounded())
        case let .belowToolbar(top): top
        }
    }

    var maximumWidth: Double {
        self == .window ? 640 : .infinity
    }

    var horizontalMargin: Double {
        self == .window ? 24 : 10
    }

    var bottomMargin: Double {
        self == .window ? 24 : 10
    }
}
