import SwiftUI

/// Zone de contenu : la carte de l'onglet sélectionné, ou les cartes de son split côte à côte, séparées par
/// des poignées réglables. Un onglet glissé depuis la barre et lâché sur le bord d'un panneau rejoint le split.
struct ContentCard: View {
    let tabManager: TabManager
    let addressBarPosition: AddressBarPosition
    let showsNavigationButtons: Bool
    /// Action du bouton Accueil ; nil pour ne pas l'afficher.
    var goHome: (() -> Void)?
    /// Ouvre la barre de commande sur l'adresse de l'onglet affiché.
    let editAddress: () -> Void
    /// Largeur cachée par la barre flottante à gauche des panneaux : pas de dépôt sur la carte dessous.
    var dropInset = 0.0

    /// Parts pendant un glissement du séparateur : état de la vue seulement, retenues à la fin.
    @State private var liveFractions: [Double]?
    /// Largeurs au début du glissement en cours.
    @State private var dragStartWidths: [Double]?
    @State private var dropTarget: SplitDropTarget?
    /// Destinataire des onglets lâchés sur les pages, reconfiguré à chaque affichage.
    @State private var dropController = SplitDropController()

    var body: some View {
        let panes = tabManager.displayedTabs
        let split = tabManager.displayedSplit
        GeometryReader { proxy in
            let widths = SplitGeometry.paneWidths(
                fractions: liveFractions ?? split?.fractions ?? [],
                count: max(panes.count, 1),
                totalWidth: proxy.size.width,
            )
            // `_ =` n'est pas permis dans un constructeur de vue.
            // swiftlint:disable:next redundant_discardable_let
            let _ = configureDropController(panes: panes, widths: widths)
            HStack(spacing: 0) {
                if panes.isEmpty {
                    pageCard(nil, isMarked: false)
                } else {
                    ForEach(Array(panes.enumerated()), id: \.element.id) { index, tab in
                        pageCard(tab, isMarked: panes.count > 1 && tab.id == tabManager.selectedTabID)
                            .frame(width: widths[index])
                        if index < panes.count - 1, let split {
                            divider(after: index, in: split, widths: widths)
                                .frame(width: SplitGeometry.gap)
                        }
                    }
                }
            }
            // Panneaux ajoutés ou retirés sans animation : une vue web ne change jamais d'hôte.
            .transaction { $0.animation = nil }
            .background {
                if panes.count > 1 {
                    PaneClickMonitor(tabs: panes) { activate($0) }
                }
            }
            .overlay {
                SplitDropHighlight(target: dropTarget, widths: widths)
                    .allowsHitTesting(false)
            }
        }
        .onChange(of: split?.id) {
            liveFractions = nil
            dragStartWidths = nil
        }
        // ⌘W, menus, split formé ou défait, autre Space : la page sélectionnée reprend le clavier si
        // personne ne l'a.
        .onChange(of: panes.map(\.id)) {
            if let tab = tabManager.selectedTab {
                TabActivation.focusPage(of: tab)
            }
        }
    }

    private func pageCard(_ tab: BrowserTab?, isMarked: Bool) -> PageCard {
        PageCard(
            tab: tab,
            isMarked: isMarked,
            addressBarPosition: addressBarPosition,
            showsNavigationButtons: showsNavigationButtons,
            goHome: goHome,
            editAddress: editAddress,
            activate: { tab.map(activate) },
            sidebarDropTarget: dropController,
        )
    }

    /// Poignée entre les panneaux `index` et `index + 1` : parts suivies pendant le glissement, écrites une
    /// fois à la fin.
    private func divider(after index: Int, in split: SplitGroup, widths: [Double]) -> SplitDivider {
        SplitDivider(
            onDrag: { translation in
                let start = dragStartWidths ?? widths
                dragStartWidths = start
                liveFractions = SplitGeometry.fractions(draggingDivider: index, by: translation, startWidths: start)
            },
            onDragEnded: {
                if let liveFractions {
                    tabManager.setSplitFractions(split.id, liveFractions)
                }
                liveFractions = nil
                dragStartWidths = nil
            },
            onReset: { tabManager.setSplitFractions(split.id, SplitGroup.equalFractions(count: widths.count)) },
            onStep: { step in
                let delta = Double(step) * SplitGeometry.accessibilityStep * widths.reduce(0, +)
                tabManager.setSplitFractions(split.id, SplitGeometry.fractions(draggingDivider: index, by: delta, startWidths: widths))
            },
        )
    }

    /// Le contrôleur n'est pas observé : le reconfigurer pendant l'affichage ne redessine rien.
    private func configureDropController(panes: [BrowserTab], widths: [Double]) {
        dropController.panes = panes
        dropController.widths = widths
        dropController.leadingInset = dropInset
        dropController.canTakeTab = canTakeTab
        dropController.onTargetChange = { dropTarget = $0 }
        dropController.onDrop = { id, target in
            guard let tab = tabManager.tab(withID: id), tabManager.openInSplit(tab, at: target.insertionIndex) else {
                return
            }
            TabActivation.activate(tab, in: tabManager)
        }
    }

    /// Un onglet sélectionné, hors des favoris, dont le split n'est pas plein. L'onglet glissé lui-même n'est
    /// vérifié qu'au dépôt (`openInSplit` refuse un onglet déjà affiché ou un favori).
    private var canTakeTab: Bool {
        guard let selected = tabManager.selectedTab, tabManager.place(of: selected) != .favorite else {
            return false
        }
        return tabManager.displayedSplit?.isFull != true
    }

    /// Rend `tab` panneau actif.
    private func activate(_ tab: BrowserTab) {
        if tabManager.selectedTabID != tab.id {
            tabManager.select(tab)
        }
    }
}
