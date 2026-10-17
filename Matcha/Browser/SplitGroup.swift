import Foundation

/// Côté d'un panneau où placer l'onglet déposé.
nonisolated enum SplitSide: Equatable, Sendable {
    case leading
    case trailing
}

/// Un onglet face au contenu affiché : il peut le rejoindre, le split est plein, ou c'est impossible.
nonisolated enum SplitAvailability: Equatable, Sendable {
    case allowed
    case full
    case unavailable
}

/// Split view : 2 à 4 onglets côte à côte, de gauche à droite (leur ordre dans la barre), avec la part
/// de largeur de chacun. Type pur.
nonisolated struct SplitGroup: Equatable, Sendable, Identifiable {
    static let paneCount = 2 ... 4

    let id: UUID
    private(set) var tabIDs: [UUID]
    /// Part de largeur de chaque panneau, dans l'ordre de `tabIDs` ; somme 1.
    private(set) var fractions: [Double]

    /// Un onglet en double n'est gardé qu'une fois ; des parts invalides deviennent des parts égales.
    init(id: UUID = UUID(), tabIDs: [UUID], fractions: [Double] = []) {
        self.id = id
        var seen: Set<UUID> = []
        let unique = tabIDs.indices.filter { seen.insert(tabIDs[$0]).inserted }
        self.tabIDs = unique.map { tabIDs[$0] }
        let kept = fractions.count == tabIDs.count ? unique.map { fractions[$0] } : fractions
        self.fractions = Self.normalizedFractions(kept, count: self.tabIDs.count)
    }

    var isFull: Bool {
        tabIDs.count >= Self.paneCount.upperBound
    }

    func contains(_ tabID: UUID) -> Bool {
        tabIDs.contains(tabID)
    }

    func index(of tabID: UUID) -> Int? {
        tabIDs.firstIndex(of: tabID)
    }

    /// Panneau voisin : à droite, sinon à gauche ; nil hors du groupe ou seul.
    func neighbor(of tabID: UUID) -> UUID? {
        guard let index = index(of: tabID), tabIDs.count > 1 else {
            return nil
        }
        return index + 1 < tabIDs.count ? tabIDs[index + 1] : tabIDs[index - 1]
    }

    /// Insère au rang `index` (borné) ; le nouveau panneau reçoit 1/(n+1), les autres × n/(n+1).
    /// Sans effet s'il y est.
    mutating func insert(_ tabID: UUID, at index: Int) {
        guard !contains(tabID) else {
            return
        }
        let count = Double(tabIDs.count)
        var shares = fractions.map { $0 * count / (count + 1) }
        let position = min(max(index, 0), tabIDs.count)
        tabIDs.insert(tabID, at: position)
        shares.insert(1 / (count + 1), at: position)
        fractions = Self.normalizedFractions(shares, count: tabIDs.count)
    }

    /// Retire le panneau ; les autres parts sont ramenées à une somme de 1.
    mutating func remove(_ tabID: UUID) {
        guard let index = index(of: tabID) else {
            return
        }
        tabIDs.remove(at: index)
        var shares = fractions
        shares.remove(at: index)
        fractions = Self.normalizedFractions(shares, count: tabIDs.count)
    }

    /// Garde `ids` (membres actuels ; les autres sont ignorés) dans cet ordre ; chaque part suit son onglet.
    mutating func setMembers(_ ids: [UUID]) {
        let shares = Dictionary(zip(tabIDs, fractions)) { first, _ in first }
        var seen: Set<UUID> = []
        let members = ids.filter { shares[$0] != nil && seen.insert($0).inserted }
        tabIDs = members
        fractions = Self.normalizedFractions(members.compactMap { shares[$0] }, count: members.count)
    }

    mutating func setFractions(_ fractions: [Double]) {
        self.fractions = Self.normalizedFractions(fractions, count: tabIDs.count)
    }

    static func equalFractions(count: Int) -> [Double] {
        count > 0 ? Array(repeating: 1 / Double(count), count: count) : []
    }

    /// `count` nombres finis > 0 : inchangés si leur somme vaut 1 à 1e-9 près, sinon divisés par leur somme ;
    /// autre chose (NaN, ≤ 0, mauvais nombre) : parts égales. `count` ≤ 0 : [].
    static func normalizedFractions(_ fractions: [Double], count: Int) -> [Double] {
        guard count > 0 else {
            return []
        }
        guard fractions.count == count, fractions.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return equalFractions(count: count)
        }
        let sum = fractions.reduce(0, +)
        guard sum.isFinite, sum > 0 else {
            return equalFractions(count: count)
        }
        return abs(sum - 1) <= 1e-9 ? fractions : fractions.map { $0 / sum }
    }
}
