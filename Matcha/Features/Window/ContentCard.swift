import SwiftUI

/// Content area: the card of the selected tab, or the cards of its split side by side, separated by adjustable
/// handles. A tab dragged from the sidebar and dropped on the edge of a pane joins the split.
/// The peek opens over the pages of all panes. A tab shown by another window offers to show it here.
struct ContentCard: View {
    let tabManager: TabManager
    /// This window's selection in the Space.
    let viewer: TabViewer
    let addressBarPosition: AddressBarPosition
    let showsNavigationButtons: Bool
    /// Action of the Home button; nil to hide it.
    var goHome: (() -> Void)?
    /// Opens the command bar on the address of the displayed tab.
    let editAddress: () -> Void
    /// Width hidden by the floating sidebar to the left of the panes: no drop on the card underneath.
    var dropInset = 0.0

    /// Fractions during a drag of the divider: view state only, kept at the end.
    @State private var liveFractions: [Double]?
    /// Widths at the start of the current drag of a divider.
    @State private var dividerDrag = ResizeDrag<[Double]>()
    @State private var dropTarget: SplitDropTarget?
    /// Receiver of tabs dropped on the pages, reconfigured on each render.
    @State private var dropController = SplitDropController()

    var body: some View {
        let panes = tabManager.displayedTabs(in: viewer)
        let split = tabManager.displayedSplit(in: viewer)
        GeometryReader { proxy in
            let widths = SplitGeometry.paneWidths(
                fractions: liveFractions ?? split?.fractions ?? [],
                count: max(panes.count, 1),
                totalWidth: proxy.size.width,
            )
            // `_ =` is not allowed in a view builder.
            // swiftlint:disable:next redundant_discardable_let
            let _ = configureDropController(panes: panes, widths: widths)
            HStack(spacing: 0) {
                if panes.isEmpty {
                    pageCard(nil, isMarked: false)
                } else {
                    ForEach(Array(panes.enumerated()), id: \.element.id) { index, tab in
                        pageCard(tab, isMarked: panes.count > 1 && tab.id == viewer.selectedTabID)
                            .frame(width: widths[index])
                        if index < panes.count - 1, let split {
                            divider(after: index, in: split, widths: widths)
                                .frame(width: SplitGeometry.gap)
                        }
                    }
                }
            }
            // Panes added or removed without animation: a web view never changes host.
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
            // The peek (Shift-click) covers the pages of all panes, not their address bar (task 4.4).
            .overlayPreferenceValue(PeekPageAreas.self) { anchors in
                GeometryReader { overlay in
                    PeekOverlay(tabManager: tabManager, viewer: viewer, pages: anchors.map { overlay[$0] }, pageCorners: pageCorners)
                }
            }
        }
        .onChange(of: split?.id) {
            liveFractions = nil
            dividerDrag.end()
        }
        // ⌘W, menus, split formed or undone, other Space: the selected page takes the keyboard back if nobody has
        // it.
        .onChange(of: panes.map(\.id)) {
            // Never a page shown by another window: it would take that window's keyboard.
            if let tab = tabManager.selectedTab(in: viewer), tabManager.shows(tab.id, in: viewer) {
                TabActivation.focusPage(of: tab)
            }
        }
    }

    /// The page of `tab` is shown by another window: this one offers to show it.
    private func isShownElsewhere(_ tab: BrowserTab?) -> Bool {
        guard let tab else {
            return false
        }
        return !tabManager.shows(tab.id, in: viewer)
    }

    private func pageCard(_ tab: BrowserTab?, isMarked: Bool) -> PageCard {
        PageCard(
            tab: tab,
            isMarked: isMarked,
            isActive: tab == nil || tab?.id == viewer.selectedTabID,
            isShownElsewhere: isShownElsewhere(tab),
            showHere: {
                tabManager.activate(viewer)
                tabManager.showHere(viewer)
                if let tab = tabManager.selectedTab(in: viewer) {
                    TabActivation.focusPage(of: tab)
                }
            },
            addressBarPosition: addressBarPosition,
            showsNavigationButtons: showsNavigationButtons,
            goHome: goHome,
            editAddress: editAddress,
            activate: { tab.map(activate) },
            sidebarDropTarget: dropController,
            siteZooms: tabManager.siteZooms,
        )
    }

    /// Handle between panes `index` and `index + 1`: fractions followed during the drag, written once at the end.
    private func divider(after index: Int, in split: SplitGroup, widths: [Double]) -> SplitDivider {
        SplitDivider(
            onDrag: { translation in
                let start = dividerDrag.begin(at: widths)
                liveFractions = SplitGeometry.fractions(draggingDivider: index, by: translation, startWidths: start)
            },
            onDragEnded: {
                if let liveFractions {
                    tabManager.setSplitFractions(split.id, liveFractions)
                }
                liveFractions = nil
                dividerDrag.end()
            },
            onReset: { tabManager.setSplitFractions(split.id, SplitGroup.equalFractions(count: widths.count)) },
            onStep: { step in
                let delta = Double(step) * SplitGeometry.accessibilityStep * widths.reduce(0, +)
                tabManager.setSplitFractions(split.id, SplitGeometry.fractions(draggingDivider: index, by: delta, startWidths: widths))
            },
        )
    }

    /// The controller is not observed: reconfiguring it during rendering redraws nothing. Its closures never capture the
    /// view, which holds the controller in its state: a cycle that kept the window's state alive (review IU3).
    private func configureDropController(panes: [BrowserTab], widths: [Double]) {
        dropController.panes = panes
        dropController.widths = widths
        dropController.leadingInset = dropInset
        dropController.canTakeTab = canTakeTab
        let target = $dropTarget
        dropController.onTargetChange = { target.wrappedValue = $0 }
        // A tab of another window is refused (review ON20): it joins a split from this window's sidebar.
        dropController.onDrop = { [weak tabManager, weak viewer] id, target in
            guard let tabManager, let viewer, let tab = tabManager.tab(withID: id) else {
                return false
            }
            tabManager.activate(viewer)
            guard tabManager.openInSplit(tab, at: target.insertionIndex) else {
                return false
            }
            TabActivation.activate(tab, in: tabManager)
            return true
        }
    }

    /// A selected tab, outside the favorites, whose split is not full. The dragged tab itself is checked only on drop
    /// (`openInSplit` refuses a tab already displayed or a favorite).
    private var canTakeTab: Bool {
        guard let selected = tabManager.selectedTab(in: viewer), tabManager.place(of: selected) != .favorite else {
            return false
        }
        return tabManager.displayedSplit(in: viewer)?.isFull != true
    }

    /// Corners of a page: those of the card, square at the top under the address bar.
    private var pageCorners: RectangleCornerRadii {
        let radius = BrowserWindowView.cardCornerRadius
        let top = addressBarPosition == .top ? 0 : radius
        return RectangleCornerRadii(topLeading: top, bottomLeading: radius, bottomTrailing: radius, topTrailing: top)
    }

    /// Makes `tab` the active pane.
    private func activate(_ tab: BrowserTab) {
        tabManager.activate(viewer)
        if viewer.selectedTabID != tab.id {
            tabManager.select(tab)
        }
    }
}
