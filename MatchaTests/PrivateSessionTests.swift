import Foundation
@testable import Matcha
import Testing
import WebKit

@MainActor
struct PrivateSessionTests {
    @Test func `private session keeps nothing on disk`() throws {
        let session = BrowserSession.makePrivate()
        #expect(session.isPrivate)
        #expect(session.isInMemory)
        let space = try #require(session.spaces.first)
        #expect(!space.tabManager.websiteDataStore.isPersistent)
        // Icons in memory only: no trace of the visited sites in the disk cache.
        let services = SessionServices()
        let other = BrowserSession.makePrivate(services: services)
        #expect(other.faviconService !== services.favicons)
        #expect(session.faviconService === space.tabManager.faviconService)
    }

    @Test func `private sessions do not share cookies`() throws {
        let first = try #require(BrowserSession.makePrivate().spaces.first)
        let second = try #require(BrowserSession.makePrivate().spaces.first)
        #expect(first.tabManager.websiteDataStore !== second.tabManager.websiteDataStore)
    }

    @Test func `regular sessions are not private`() throws {
        let services = SessionServices()
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true), services: services)
        #expect(!session.isPrivate)
        #expect(session.faviconService === services.favicons)
    }
}
