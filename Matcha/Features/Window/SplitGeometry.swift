import Foundation

/// Endroit d'un dépôt sur la carte : le bord gauche ou droit d'un panneau.
nonisolated struct SplitDropTarget: Equatable, Sendable {
    let paneIndex: Int
    let side: SplitSide

    /// Rang du nouvel onglet parmi les panneaux.
    var insertionIndex: Int {
        side == .leading ? paneIndex : paneIndex + 1
    }
}

/// Disposition des panneaux d'un split dans la carte : largeurs, séparateurs, zones de dépôt. Type pur.
nonisolated enum SplitGeometry {
    /// Intervalle entre deux cartes ; égal à `BrowserWindowView.cardMargin` (vérifié par un test).
    static let gap = 8.0
    static let minimumPaneWidth = 200.0
    /// Pas VoiceOver : part de la largeur des panneaux.
    static let accessibilityStep = 0.05

    /// Largeurs en points entiers des `count` panneaux dans `totalWidth`, intervalles compris : selon les
    /// parts, chaque panneau ayant au moins `minimumPaneWidth` (pris aux autres en proportion), ou des
    /// largeurs égales si la place manque. Les parts ne sont jamais réécrites.
    static func paneWidths(fractions: [Double], count: Int, totalWidth: Double) -> [Double] {
        guard count > 0 else {
            return []
        }
        let available = max(0, totalWidth - gap * Double(count - 1))
        let shares = SplitGroup.normalizedFractions(fractions, count: count)
        let floor = min(minimumPaneWidth, available / Double(count))
        var widths = shares.map { $0 * available }
        var isFixed = Array(repeating: false, count: count)
        for _ in 0 ..< count {
            let narrow = widths.indices.filter { !isFixed[$0] && widths[$0] < floor - 1e-6 }
            guard !narrow.isEmpty else {
                break
            }
            for index in narrow {
                isFixed[index] = true
                widths[index] = floor
            }
            let free = widths.indices.filter { !isFixed[$0] }
            let remaining = available - floor * Double(count - free.count)
            let shareSum = free.reduce(0) { $0 + shares[$1] }
            for index in free {
                widths[index] = shareSum > 0 ? remaining * shares[index] / shareSum : remaining / Double(free.count)
            }
        }
        // Bords cumulés arrondis : aucune erreur d'arrondi ne s'accumule sur un panneau.
        var result: [Double] = []
        var sum = 0.0
        var previousEdge = 0.0
        for (index, width) in widths.enumerated() {
            sum += width
            let edge = index == count - 1 ? available : sum.rounded()
            result.append(edge - previousEdge)
            previousEdge = edge
        }
        return result
    }

    /// Bord gauche de chaque panneau, intervalles compris.
    static func paneOrigins(widths: [Double]) -> [Double] {
        var origins: [Double] = []
        var origin = 0.0
        for width in widths {
            origins.append(origin)
            origin += width + gap
        }
        return origins
    }

    /// Parts après un glissement de `delta` points du séparateur `index` (entre les panneaux `index` et
    /// `index + 1`) depuis `startWidths` : seuls ces deux panneaux changent, sans passer sous la largeur minimale.
    static func fractions(draggingDivider index: Int, by delta: Double, startWidths: [Double]) -> [Double] {
        guard index >= 0, index + 1 < startWidths.count else {
            return normalized(startWidths)
        }
        var widths = startWidths
        let pair = widths[index] + widths[index + 1]
        let lower = min(minimumPaneWidth, pair / 2)
        let leading = min(max(widths[index] + delta, lower), pair - lower)
        widths[index] = leading
        widths[index + 1] = pair - leading
        return normalized(widths)
    }

    /// Largeur de la bande de dépôt de chaque bord d'un panneau : un quart, entre 60 et 180 pt, la moitié au plus.
    static func dropZoneWidth(forPaneWidth width: Double) -> Double {
        min(max(width * 0.25, 60), 180, width / 2)
    }

    /// Bord de panneau sous l'abscisse `position` (depuis le bord gauche des panneaux) ; nil au milieu d'un
    /// panneau ou dans un intervalle.
    static func dropTarget(atX position: Double, widths: [Double]) -> SplitDropTarget? {
        for (index, origin) in paneOrigins(widths: widths).enumerated() {
            let width = widths[index]
            guard origin <= position, position < origin + width else {
                continue
            }
            let zone = dropZoneWidth(forPaneWidth: width)
            if position - origin <= zone {
                return SplitDropTarget(paneIndex: index, side: .leading)
            }
            if origin + width - position <= zone {
                return SplitDropTarget(paneIndex: index, side: .trailing)
            }
            return nil
        }
        return nil
    }

    private static func normalized(_ widths: [Double]) -> [Double] {
        let sum = widths.reduce(0, +)
        guard sum > 0, sum.isFinite else {
            return SplitGroup.equalFractions(count: widths.count)
        }
        return widths.map { $0 / sum }
    }
}
