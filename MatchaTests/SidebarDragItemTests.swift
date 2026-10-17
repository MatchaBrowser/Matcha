import Foundation
@testable import Matcha
import Testing

struct SidebarDragItemTests {
    @Test func `tab and folder survive the round trip through text`() {
        let id = UUID()
        #expect(SidebarDragItem(text: SidebarDragItem.tab(id).text) == .tab(id))
        #expect(SidebarDragItem(text: SidebarDragItem.folder(id).text) == .folder(id))
        #expect(SidebarDragItem.tab(id) != .folder(id))
    }

    @Test(arguments: ["", "bonjour", "https://example.com", "matcha-tab:", "matcha-tab:pas-un-uuid", UUID().uuidString])
    func `other text is not a sidebar item`(text: String) {
        #expect(SidebarDragItem(text: text) == nil)
    }
}
