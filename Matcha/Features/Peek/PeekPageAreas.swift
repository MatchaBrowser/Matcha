import SwiftUI

/// Pages des panneaux affichés (sans leur barre d'adresse), relevées par chaque `PageCard` : l'aperçu se place
/// sur leur réunion et voile chacune (tâche 4.4).
nonisolated struct PeekPageAreas: PreferenceKey {
    static var defaultValue: [Anchor<CGRect>] {
        []
    }

    static func reduce(value: inout [Anchor<CGRect>], nextValue: () -> [Anchor<CGRect>]) {
        value += nextValue()
    }
}
