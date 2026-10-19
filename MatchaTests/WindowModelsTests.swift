import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Models of a window and a private window's session, made once (audit R5).
@MainActor
struct WindowModelsTests {
    @Test func `a window's models are made once and share the window model`() throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let models = WindowModels(session: session)
        #expect(models.window === models.window)
        #expect(models.commandBar === models.commandBar)
        #expect(models.commandBar.windowModel === models.window)
    }

    @Test func `a private session is made once, when first read`() {
        let holder = PrivateSessionHolder(services: SessionServices())
        let session = holder.session
        #expect(holder.session === session)
        #expect(session.isPrivate)
    }

    @Test func `a private session goes away with its window`() {
        weak var released: BrowserSession?
        do {
            let holder = PrivateSessionHolder(services: SessionServices())
            released = holder.session
            #expect(released != nil)
        }
        #expect(released == nil)
    }
}
