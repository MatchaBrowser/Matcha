import Foundation
@testable import Matcha
import Testing

struct MiniWindowTargetTests {
    private let personal = UUID()
    private let work = UUID()
    private let home = UUID()
    private let office = UUID()
    private let side = UUID()

    /// Home (personal), Office (work), Side projects (personal), in sidebar order.
    private var spaces: [MiniWindowTarget.Space] {
        [.init(id: home, profileID: personal), .init(id: office, profileID: work), .init(id: side, profileID: personal)]
    }

    @Test func `displayed space of the same profile is the target`() {
        #expect(MiniWindowTarget.defaultSpaceID(profileID: personal, displayedSpaceID: side, spaces: spaces) == side)
    }

    @Test func `displayed space of another profile gives the first space of the profile`() {
        #expect(MiniWindowTarget.defaultSpaceID(profileID: personal, displayedSpaceID: office, spaces: spaces) == home)
        #expect(MiniWindowTarget.defaultSpaceID(profileID: work, displayedSpaceID: side, spaces: spaces) == office)
    }

    @Test func `no space of the profile left gives the displayed space, otherwise the first`() {
        #expect(MiniWindowTarget.defaultSpaceID(profileID: UUID(), displayedSpaceID: office, spaces: spaces) == office)
        #expect(MiniWindowTarget.defaultSpaceID(profileID: UUID(), displayedSpaceID: nil, spaces: spaces) == home)
        #expect(MiniWindowTarget.defaultSpaceID(profileID: UUID(), displayedSpaceID: UUID(), spaces: spaces) == home)
    }

    @Test func `no space gives nil`() {
        #expect(MiniWindowTarget.defaultSpaceID(profileID: personal, displayedSpaceID: nil, spaces: []) == nil)
    }
}
