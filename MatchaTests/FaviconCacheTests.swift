import Foundation
@testable import Matcha
import SwiftData
import Testing

/// Website icons kept on disk (review SV1 and SV3): erased with the history and a website's data, bounded, read once.
@MainActor
struct FaviconCacheTests {
    private let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("FaviconCacheTests-\(UUID().uuidString)", isDirectory: true)

    private func files() -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
    }

    /// The icon of `host`, kept in memory and on disk.
    private func cache(_ host: String, in service: FaviconService) async throws {
        let page = try #require(URL(string: "https://\(host)/"))
        #expect(await service.fetchIcon(forPage: page, candidates: [FaviconCandidate(url: FaviconServiceTests.pngURL, rel: "icon")]) != nil)
    }

    @Test func `erasing keeps only the icons still needed`() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FaviconService(directory: directory)
        for host in ["a.example", "b.example", "c.example"] {
            try await cache(host, in: service)
        }
        await service.removeIcon(forHost: "c.example")
        #expect(files() == ["a.example", "b.example"])
        await service.removeIcons(keeping: ["a.example"])
        #expect(files() == ["a.example"])
        #expect(service.cachedIcon(forHost: "b.example") == nil)
        #expect(await service.loadCachedIcon(forHost: "a.example") != nil)
    }

    @Test func `the cache keeps the most recent files`() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (offset, name) in ["old", "middle", "recent"].enumerated() {
            let file = directory.appendingPathComponent(name)
            try Data([1]).write(to: file)
            try FileManager.default.setAttributes(
                [.modificationDate: Date(timeIntervalSinceNow: Double(offset - 10) * 60)],
                ofItemAtPath: file.path,
            )
        }
        await FaviconDiskCache(directory: directory).trim(to: 2)
        #expect(files() == ["middle", "recent"])
    }

    @Test func `tabs of the same website read its file once`() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let writer = FaviconService(directory: directory)
        try await cache("a.example", in: writer)
        await writer.waitForDisk()
        let service = FaviconService(directory: directory)
        async let first = service.loadCachedIcon(forHost: "a.example")
        async let second = service.loadCachedIcon(forHost: "a.example")
        let (one, two) = await (first, second)
        #expect(one != nil && one === two)
    }

    /// Clearing the history erases the icons of the websites no longer visited, never those of a favorite.
    @Test func `clearing the history forgets the icons of the websites gone`() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = FaviconService(directory: directory)
        let session = try BrowserSession(
            container: BrowserSchema.makeContainer(inMemory: true),
            services: SessionServices(favicons: service),
        )
        let history = try #require(session.history)
        await history.load()
        let profileID = session.spaces[0].openedProfileID
        for host in ["visited.example", "favorite.example"] {
            try await cache(host, in: service)
            try history.recordVisit(url: #require(URL(string: "https://\(host)/")), title: nil, profileID: profileID, spaceID: nil)
        }
        let favorite = TabRecord(url: URL(string: "https://favorite.example/"), place: .favorite)
        session.container.mainContext.insert(favorite)
        await service.waitForDisk()
        #expect(files() == ["visited.example", "favorite.example"])

        history.clear(.allHistory, profileID: profileID)
        try await waitUntil { files() == ["favorite.example"] }
    }
}
