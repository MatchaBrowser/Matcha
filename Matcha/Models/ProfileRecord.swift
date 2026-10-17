import Foundation
import SwiftData

/// Profil enregistré : ses Spaces partagent cookies et données des sites, et ses favoris.
@Model
final class ProfileRecord {
    var id = UUID()
    var name = ""
    var order = 0
    @Relationship(deleteRule: .cascade, inverse: \SpaceRecord.profile) var spaces: [SpaceRecord]? = []
    /// Favoris du profil, communs à tous ses Spaces.
    @Relationship(deleteRule: .cascade, inverse: \TabRecord.profile) var favorites: [TabRecord]? = []

    init(id: UUID = UUID(), name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
    }
}
