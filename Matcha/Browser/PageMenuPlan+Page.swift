import Foundation

/// Commande de Matcha dans le menu contextuel d'une page (clic droit hors d'un lien, d'une image ou d'un texte
/// sélectionné) : précédent, suivant, enregistrer sous, imprimer, code source.
nonisolated enum PageCommand: String, CaseIterable, Sendable {
    case goBack = "GoBack"
    case goForward = "GoForward"
    case saveAs = "SaveAs"
    case print = "Print"
    case viewSource = "ViewSource"

    /// Identifiant de l'élément de menu, sur le modèle de ceux de WebKit.
    var identifier: String {
        "MatchaMenuItemIdentifier" + rawValue
    }
}

/// Une ligne du menu d'une page réécrit : un élément de WebKit (par sa place dans le menu d'origine), une commande de
/// Matcha, ou un séparateur.
nonisolated enum PageMenuEntry: Equatable, Sendable {
    case webKit(Int)
    case command(PageCommand)
    case separator
}

nonisolated extension PageMenuPlan {
    /// « Recharger » de WebKit : il n'est que dans le menu d'une page (pas d'un lien, d'une image ni d'un texte).
    static let reloadIdentifier = "WKMenuItemIdentifierReload"
    /// « Précédent » et « Suivant » de WebKit, quand il les met : remplacés par ceux de Matcha, toujours présents.
    static let historyIdentifiers: Set<String> = ["WKMenuItemIdentifierGoBack", "WKMenuItemIdentifierGoForward"]
    /// « Inspecter l'élément » (outils pour développeurs) : gardé en dernier.
    static let inspectIdentifier = "WKMenuItemIdentifierInspectElement"

    /// Menu d'une page, comme dans Chrome : Précédent, Suivant, Recharger ; Enregistrer sous…, Imprimer… ; les autres
    /// éléments de WebKit ; Afficher le code source, puis « Inspecter l'élément » s'il y est. `identifiers` : ceux des
    /// éléments du menu d'origine, dans l'ordre (nil sans identifiant) ; `separators` : la place de ses séparateurs,
    /// remplacés par ceux de Matcha. nil si ce n'est pas le menu d'une page.
    static func pageLayout(for identifiers: [String?], separators: Set<Int>) -> [PageMenuEntry]? {
        guard let reload = identifiers.firstIndex(of: reloadIdentifier) else {
            return nil
        }
        let inspect = identifiers.firstIndex(of: inspectIdentifier)
        let others = identifiers.indices.filter { index in
            index != reload && index != inspect && !separators.contains(index)
                && !(identifiers[index].map(historyIdentifiers.contains) ?? false)
        }
        var entries: [PageMenuEntry] = [.command(.goBack), .command(.goForward), .webKit(reload)]
        entries += [.separator, .command(.saveAs), .command(.print)]
        if !others.isEmpty {
            entries.append(.separator)
            entries += others.map(PageMenuEntry.webKit)
        }
        entries += [.separator, .command(.viewSource)]
        if let inspect {
            entries.append(.webKit(inspect))
        }
        return entries
    }
}
