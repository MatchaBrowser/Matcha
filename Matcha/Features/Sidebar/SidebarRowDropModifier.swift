import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Accepts a dragged tab, split or folder on a row or a tile, following the pointer (`DropDelegate`, the only drop
/// API that reports where the pointer is during the drag): `part` is the part of the row the item would go to
/// (`SidebarRowDrop`), for the row to show it; on drop, the item goes to that part's destination (`SidebarDropAction`).
struct SidebarRowDropModifier: ViewModifier {
    let tabManager: TabManager
    let drop: SidebarRowDrop
    /// Direction in which the parts follow each other: vertical for a row, horizontal for a tile.
    let axis: Axis
    @Binding var part: SidebarRowDrop.Part?

    @Environment(WindowModel.self) private var windowModel: WindowModel?
    /// Length of the view along `axis`.
    @State private var length = 0.0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: Double.self) { [axis] in axis == .vertical ? $0.size.height : $0.size.width } action: {
                length = $0
            }
            .onDrop(of: [.matchaSidebarItem], delegate: Delegate(
                action: SidebarDropAction(tabManager: tabManager, windowModel: windowModel),
                drop: drop,
                axis: axis,
                length: $length,
                part: $part,
            ))
    }

    private struct Delegate: DropDelegate {
        let action: SidebarDropAction
        let drop: SidebarRowDrop
        let axis: Axis
        @Binding var length: Double
        @Binding var part: SidebarRowDrop.Part?

        func validateDrop(info: DropInfo) -> Bool {
            info.hasItemsConforming(to: [.matchaSidebarItem])
        }

        func dropEntered(info: DropInfo) {
            show(part(under: info))
        }

        /// nil: SwiftUI's default operation (copy), which every drag source allows.
        func dropUpdated(info: DropInfo) -> DropProposal? {
            show(part(under: info))
            return nil
        }

        func dropExited(info _: DropInfo) {
            show(nil)
        }

        /// An item of this app is already on the drag pasteboard: the answer is the action's, so a refused item goes
        /// back to its place (review ON20). Otherwise its data is read after the drop, as `dropDestination` does.
        func performDrop(info: DropInfo) -> Bool {
            let target = drop.destination(for: part(under: info))
            show(nil)
            if let data = NSPasteboard(name: .drag).data(forType: BrowserWebView.sidebarItemType), let item = SidebarDragItem(data: data) {
                return action.perform(item, at: target)
            }
            guard let provider = info.itemProviders(for: [.matchaSidebarItem]).first else {
                return false
            }
            _ = provider.loadTransferable(type: SidebarDragItem.self) { [action] result in
                guard case let .success(item) = result else {
                    return
                }
                Task { @MainActor in
                    _ = action.perform(item, at: target)
                }
            }
            return true
        }

        private func part(under info: DropInfo) -> SidebarRowDrop.Part {
            drop.part(at: axis == .vertical ? info.location.y : info.location.x, length: length)
        }

        private func show(_ newPart: SidebarRowDrop.Part?) {
            if part != newPart {
                withMotion(.easeOut(duration: 0.1)) { part = newPart }
            }
        }
    }
}

extension View {
    /// Accepts a dragged item on a row (`axis` vertical) or a tile (horizontal), following the pointer: `part` is where
    /// it would go, for the row to show it (`SidebarRowDropModifier`).
    func sidebarRowDropDestination(
        tabManager: TabManager,
        drop: SidebarRowDrop,
        axis: Axis = .vertical,
        part: Binding<SidebarRowDrop.Part?>,
    ) -> some View {
        modifier(SidebarRowDropModifier(tabManager: tabManager, drop: drop, axis: axis, part: part))
    }

    /// Insertion line of a row: at its top for `.before`, at its bottom for `.after`, indented by `afterIndent` (first
    /// item of an expanded folder).
    func insertionLine(for part: SidebarRowDrop.Part?, afterIndent: Double = 0) -> some View {
        overlay(alignment: .top) {
            if part == .before {
                InsertionLine(edge: .top)
            }
        }
        .overlay(alignment: .bottom) {
            if part == .after {
                InsertionLine(edge: .bottom)
                    .padding(.leading, afterIndent)
            }
        }
    }
}

/// Line marking where the dragged item will be inserted, centered on the top or bottom edge of a row.
struct InsertionLine: View {
    /// Also that of the line between two favorite tiles.
    static let thickness = 4.0

    var edge = VerticalEdge.top

    var body: some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(height: Self.thickness)
            .offset(y: (edge == .top ? -1 : 1) * Self.thickness / 2)
    }
}
