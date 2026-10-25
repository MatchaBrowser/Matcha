import Foundation
@testable import Matcha
import Testing

/// Today tabs of the other Macs (`SYNC.md` § 2.4): published by each Mac in one record, only shown by the others.
@MainActor
struct DeviceTabsTests {
    private let device = UUID()
    private let space = UUID()
    private let server = InMemorySyncServer()

    private func local(_ tabs: [(String?, String?)], id: UUID? = nil, name: String = "Home") -> SyncDeviceTabsFields.LocalSpace {
        SyncDeviceTabsFields.LocalSpace(id: id ?? space, name: name, tabs: tabs.map { ($0.0.flatMap(URL.init(string:)), $0.1) })
    }

    private func fields(_ name: String = "MacBook", device: UUID? = nil, url: String = "https://example.com") -> SyncDeviceTabsFields {
        .publishing(deviceId: device ?? self.device, name: name, spaces: [local([(url, "Example")])])
    }

    // MARK: Fields

    @Test func `only web addresses travel, without credentials, titles cut, empty Spaces left out`() throws {
        let long = "https://example.com/" + String(repeating: "a", count: SyncDeviceTabsFields.maximumURLLength)
        let title = String(repeating: "t", count: 400)
        let published = SyncDeviceTabsFields.publishing(deviceId: device, name: "MacBook", spaces: [
            local([
                ("https://user:secret@example.com/a", title),
                ("file:///Users/Shared/notes.html", "Notes"),
                ("about:blank", nil),
                (nil, nil),
                (long, nil),
                ("https://example.org", "  "),
            ]),
            local([("file:///tmp/x.html", nil)], id: UUID(), name: "Empty"),
        ])
        let tabs = try #require(published.spaces.first).tabs
        #expect(published.spaces.count == 1)
        #expect(tabs.map(\.url.absoluteString) == ["https://example.com/a", "https://example.org"])
        #expect(tabs.first?.title?.count == SyncDeviceTabsFields.maximumTitleLength)
        #expect(tabs.last?.title == "  ")
    }

    @Test func `beyond the limits, the last tabs are left out, Space by Space`() throws {
        let many = (0 ..< 600).map { ("https://example.com/\($0)", Optional("Tab \($0)")) }
        let capped = SyncDeviceTabsFields.publishing(
            deviceId: device,
            name: "Mac",
            spaces: [local(many), local([("https://after.example", nil)], id: UUID())],
        )
        #expect(capped.spaces.flatMap(\.tabs).count == SyncDeviceTabsFields.maximumTabs)
        #expect(capped.spaces.count == 1)

        let heavy = (0 ..< 200).map { ("https://example.com/\($0)/" + String(repeating: "x", count: 2000), String?.none) }
        let sized = SyncDeviceTabsFields.publishing(deviceId: device, name: "Mac", spaces: [local(heavy)])
        let size = try SyncCoding.encoder().encode(sized).count
        #expect(size <= SyncDeviceTabsFields.maximumEncodedSize)
        #expect(sized.spaces.first?.tabs.count ?? 0 < 200)
    }

    @Test func `a received record is read leniently and has a derived identifier`() throws {
        let json = try SyncCoding.decoder().decode(SyncJSON.self, from: Data("""
        {"deviceId":"\(device.uuidString)","spaces":[
            {"spaceId":"\(space.uuidString)","name":"Home","tabs":[
                {"url":"javascript:alert(1)"},{"url":"https://example.com","title":"Ex"}
            ]},
            {"name":"No identifier","tabs":[]}
        ]}
        """.utf8))
        guard case let .deviceTabs(read)? = SyncFields(json: json, type: .deviceTabs) else {
            Issue.record("Record unreadable")
            return
        }
        let url = try #require(URL(string: "https://example.com"))
        #expect(read.name.isEmpty)
        #expect(read.spaces.map(\.spaceId) == [space])
        #expect(read.spaces.first?.tabs == [SyncDeviceTabsFields.Tab(url: url, title: "Ex")])
        #expect(SyncFields(json: .object(["name": .string("Mac")]), type: .deviceTabs) == nil)
        #expect(SyncIdentifiers.testAccount.expectedID(of: .deviceTabs(read)) == SyncIdentifiers.testAccount.deviceTabs(device))
        #expect(SyncIdentifiers.testAccount.deviceTabs(device) != SyncIdentifiers.testAccount.deviceTabs(UUID()))
    }

    // MARK: Engine

    @Test func `a change of this Mac's tabs waits to be stable, and at most once a minute`() async throws {
        let mac = SimulatedMac(server: server)
        let id = SyncIdentifiers.testAccount.deviceTabs(device)
        mac.store.items[id] = .deviceTabs(fields())
        #expect(try await mac.sync()?.sent == 1)

        mac.store.items[id] = .deviceTabs(fields(url: "https://example.com/2"))
        #expect(try await mac.sync(after: 1)?.sent == 0)
        #expect(mac.engine.nextCheck == mac.time + SyncChangeDetector.stability)
        #expect(try await mac.sync(after: 5)?.sent == 1)
        let sentAt = mac.time

        mac.store.items[id] = .deviceTabs(fields(url: "https://example.com/3"))
        #expect(try await mac.sync(after: 6)?.sent == 0)
        #expect(mac.engine.nextCheck == sentAt + SyncChangeDetector.minimumInterval)
        #expect(try await mac.sync(after: 60)?.sent == 1)

        // Withdrawn (signing out): the deletion leaves at once.
        mac.store.items[id] = nil
        #expect(try await mac.sync()?.sent == 1)
        #expect(await server.content(of: id)?.deleted == true)
    }

    @Test func `the tabs of a revoked Mac are deleted, those of an unknown one are not`() async throws {
        let other = SimulatedMac(server: server)
        let id = SyncIdentifiers.testAccount.deviceTabs(device)
        other.store.items[id] = .deviceTabs(fields())
        try await other.sync()
        let mac = SimulatedMac(server: server)
        try await mac.sync()
        #expect(OtherMac.all(in: mac.engine.state, now: mac.time).map(\.id) == [device])

        mac.engine.queueDeletion(of: id, type: .deviceTabs)
        mac.engine.queueDeletion(of: SyncIdentifiers.testAccount.deviceTabs(UUID()), type: .deviceTabs)
        #expect(mac.engine.state.pending.count == 1)
        #expect(OtherMac.all(in: mac.engine.state, now: mac.time).isEmpty)
        #expect(try await mac.sync()?.sent == 1)
        #expect(await server.content(of: id)?.deleted == true)
    }

    // MARK: Shown

    @Test func `the other Macs shown: neither this one, nor deleted, nor too old, by name`() {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        var state = SyncState(deviceID: device)
        func add(_ fields: SyncDeviceTabsFields, at modifiedAt: Date = date, deleted: Bool = false) {
            let content = deleted
                ? SyncContent.deletion(of: "deviceTabs", schema: 1, modifiedAt: modifiedAt, modifiedBy: fields.deviceId)
                : SyncContent(fields: .deviceTabs(fields), modifiedAt: modifiedAt, modifiedBy: fields.deviceId)
            state.entries[SyncIdentifiers.testAccount.deviceTabs(fields.deviceId)] = SyncEntry(
                type: "deviceTabs",
                version: 1,
                remote: content,
            )
        }
        add(fields("This Mac"))
        add(fields("mac mini", device: UUID()))
        add(fields("Air", device: UUID()))
        add(fields("Gone", device: UUID()), deleted: true)
        add(fields("Old", device: UUID()), at: date.addingTimeInterval(-OtherMac.maximumAge - 1))
        add(SyncDeviceTabsFields(deviceId: UUID(), name: "Empty", spaces: []))
        #expect(OtherMac.all(in: state, now: date).map(\.name) == ["Air", "mac mini"])
    }

    @Test func `this Mac's today tabs are in the snapshot, by Space in order, until it signs out`() throws {
        let session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        let suite = "DeviceTabsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = MatchaSyncStore(
            session: session,
            defaults: defaults,
            identifiers: .testAccount,
            device: SyncDeviceDescription(id: device, name: "MacBook"),
        )
        let home = try #require(session.spaces.first)
        let pinned = home.tabManager.newTab(url: URL(string: "https://example.com/pinned"), select: false)
        home.tabManager.setPlace(pinned, to: .pinned)
        home.tabManager.newTab(url: URL(string: "https://example.com/first"))
        home.tabManager.newTab(url: URL(string: "https://example.com/second"))
        home.saveNow()
        let id = SyncIdentifiers.testAccount.deviceTabs(device)
        guard case let .deviceTabs(published)? = try store.snapshot()[id] else {
            Issue.record("This Mac's tabs missing")
            return
        }
        #expect(published.name == "MacBook")
        #expect(published.spaces.map(\.spaceId) == [home.id])
        #expect(published.spaces.first?.name == home.record.name)
        #expect(published.spaces.first?.tabs.map(\.url.absoluteString) == home.tabManager.todayTabs.compactMap(\.url?.absoluteString))

        store.publishesDeviceTabs = false
        #expect(try store.snapshot()[id] == nil)
    }

    // MARK: Command bar

    @Test func `the command bar offers the other Macs' tabs, below this Mac's tabs and actions, above history`() async {
        let otherMacs = OtherMacsTabs()
        var state = SyncState(deviceID: UUID())
        let published = SyncDeviceTabsFields.publishing(deviceId: device, name: "MacBook", spaces: [
            local([("https://github.com/matchabrowser", "GitHub Matcha")]),
        ])
        state.entries[SyncIdentifiers.testAccount.deviceTabs(device)] = SyncEntry(
            type: "deviceTabs",
            version: 1,
            remote: SyncContent(fields: .deviceTabs(published), modifiedAt: fixedNow, modifiedBy: device),
        )
        otherMacs.update(from: state, now: fixedNow)
        let provider = OtherMacsTabsProvider(otherMacs: otherMacs)
        #expect(await provider.candidates(for: query("git"), context: CommandContext(isPrivate: true)).isEmpty)
        let remote = await provider.candidates(for: query("git"), context: CommandContext())
        #expect(remote.map(\.kind) == [.otherMacTab(deviceID: device, deviceName: "MacBook", modifiedAt: fixedNow)])

        let local = tab("GitHub issues", url: "https://github.com/issues")
        let visited = history("GitHub home", url: "https://github.com/home", visits: 50)
        let sameAddress = history("Example", url: "https://github.com/matchabrowser", visits: 50)
        let rows = CommandRanker().rank(query("git"), candidates: remote + [visited, sameAddress, local], now: fixedNow)
        // The history of an address open on another Mac is not shown twice.
        #expect(rows.filter { !$0.id.hasPrefix(CommandPrimaryRows.id) }.map(\.title) == ["GitHub issues", "GitHub Matcha", "GitHub home"])
        #expect(rows.first { $0.style == .otherMacTab(deviceName: "MacBook") }?.target == .open(published.spaces[0].tabs[0].url))
    }
}
