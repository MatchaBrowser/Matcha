import Foundation
import SwiftData

/// Saved profile: its Spaces share cookies and website data, and its favorites.
@Model
final class ProfileRecord {
    var id = UUID()
    var name = ""
    var order = 0
    @Relationship(deleteRule: .cascade, inverse: \SpaceRecord.profile) var spaces: [SpaceRecord]? = []
    /// The profile's favorites, shared by all its Spaces.
    @Relationship(deleteRule: .cascade, inverse: \TabRecord.profile) var favorites: [TabRecord]? = []

    init(id: UUID = UUID(), name: String, order: Int = 0) {
        self.id = id
        self.name = name
        self.order = order
    }
}
