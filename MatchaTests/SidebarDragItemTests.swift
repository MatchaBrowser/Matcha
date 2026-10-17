import CoreTransferable
import Foundation
@testable import Matcha
import Testing
import UniformTypeIdentifiers

struct SidebarDragItemTests {
    @Test func `tab, split and folder survive the round trip through text and data`() {
        let id = UUID()
        for item in [SidebarDragItem.tab(id), .folder(id), .split(id)] {
            #expect(SidebarDragItem(text: item.text) == item)
            #expect(SidebarDragItem(data: Data(item.text.utf8)) == item)
        }
        #expect(SidebarDragItem.tab(id) != .folder(id))
        #expect(SidebarDragItem.split(id) != .tab(id))
    }

    @Test(arguments: ["", "bonjour", "https://example.com", "matcha-tab:", "matcha-tab:pas-un-uuid", "matcha-split:", UUID().uuidString])
    func `other text is not a sidebar item`(text: String) {
        #expect(SidebarDragItem(text: text) == nil)
    }

    @Test func `items travel as private data`() {
        let type = UTType.matchaSidebarItem
        #expect(type.isDynamic)
        #expect(type.conforms(to: .data))
        #expect(!type.conforms(to: .text))
        #expect(!type.conforms(to: .plainText))
        #expect(!type.conforms(to: .url))
        // Le même identifiant à chaque lancement : le glisser d'une fenêtre reste lisible par une autre.
        #expect(UTType(mimeType: "application/x-matcha-sidebar-item", conformingTo: .data)?.identifier == type.identifier)
    }

    @Test func `the transfer representation carries only the private type`() async throws {
        #expect(SidebarDragItem.exportedContentTypes() == [.matchaSidebarItem])
        #expect(SidebarDragItem.importedContentTypes() == [.matchaSidebarItem])
        let item = SidebarDragItem.split(UUID())
        let data = try await item.exported(as: .matchaSidebarItem)
        #expect(SidebarDragItem(data: data) == item)
        let imported = try await SidebarDragItem(importing: data, contentType: .matchaSidebarItem)
        #expect(imported == item)
        // CoreTransferable enveloppe l'erreur de l'importation dans la sienne.
        await #expect(throws: (any Error).self) {
            _ = try await SidebarDragItem(importing: Data("bonjour".utf8), contentType: .matchaSidebarItem)
        }
    }

    @Test func `data round trip refuses foreign bytes`() {
        #expect(SidebarDragItem(data: Data([0xFF, 0xFE, 0x00])) == nil)
        #expect(SidebarDragItem(data: Data("https://example.com".utf8)) == nil)
        #expect(SidebarDragItem(data: Data()) == nil)
    }
}
