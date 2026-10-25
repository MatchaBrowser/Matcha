import Foundation

/// Today tabs of one Mac, read-only for the others (`SYNC.md` § 2.4): one `deviceTabs` record per Mac, written by that
/// Mac only and never placed in another Mac's sidebar. Read leniently: an unreadable Space or tab is left out. Pure type.
nonisolated struct SyncDeviceTabsFields: Codable, Equatable, Sendable {
    /// A tab: its web address and its title.
    struct Tab: Codable, Equatable, Sendable {
        var url: URL
        var title: String?

        init(url: URL, title: String?) {
            self.url = url
            self.title = title
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard let url = container.lenient(String.self, forKey: .url).flatMap(URL.init(string:)), SyncWebURL.isWeb(url) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a web address"))
            }
            self.url = url
            title = container.lenient(String.self, forKey: .title)
        }
    }

    /// A Space of that Mac, with its name there and its today tabs in sidebar order.
    struct Space: Codable, Equatable, Sendable {
        var spaceId: UUID
        var name: String
        var tabs: [Tab]

        init(spaceId: UUID, name: String, tabs: [Tab]) {
            self.spaceId = spaceId
            self.name = name
            self.tabs = tabs
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            spaceId = try container.required(UUID.self, forKey: .spaceId)
            name = container.lenient(String.self, forKey: .name) ?? ""
            tabs = (container.lenient([Lenient<Tab>].self, forKey: .tabs) ?? []).compactMap(\.value)
        }
    }

    var deviceId: UUID
    var name: String
    var spaces: [Space]

    static let maximumTabs = 500
    static let maximumURLLength = 2048
    static let maximumTitleLength = 300
    /// Encoded fields, under the server's 256 KiB per encrypted content (`SYNC.md` § 4.1).
    static let maximumEncodedSize = 200 * 1024

    init(deviceId: UUID, name: String, spaces: [Space]) {
        self.deviceId = deviceId
        self.name = name
        self.spaces = spaces
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        deviceId = try container.required(UUID.self, forKey: .deviceId)
        name = container.lenient(String.self, forKey: .name) ?? ""
        spaces = (container.lenient([Lenient<Space>].self, forKey: .spaces) ?? []).compactMap(\.value)
    }

    /// Tabs of a Space of this Mac, before they are published.
    struct LocalSpace {
        var id: UUID
        var name: String
        var tabs: [(url: URL?, title: String?)]
    }

    /// This Mac's tabs as they travel: web addresses only, without user name nor password and not too long, titles cut,
    /// empty Spaces left out. Beyond `maximumTabs` or `maximumEncodedSize`, the last tabs are left out, Space by Space in
    /// order.
    static func publishing(deviceId: UUID, name: String, spaces: [LocalSpace]) -> SyncDeviceTabsFields {
        let encoder = SyncCoding.encoder()
        func size(of value: some Encodable) -> Int {
            (try? encoder.encode(value).count) ?? 0
        }
        var fields = SyncDeviceTabsFields(deviceId: deviceId, name: name, spaces: [])
        var total = size(of: fields)
        var count = 0
        var isFull = false
        for local in spaces where !isFull {
            var space = Space(spaceId: local.id, name: local.name, tabs: [])
            var spaceSize = size(of: space) + 1
            for (address, title) in local.tabs {
                guard let url = SyncWebURL.shared(address), url.absoluteString.count <= maximumURLLength else {
                    continue
                }
                let tab = Tab(url: url, title: title.map { String($0.prefix(maximumTitleLength)) }.flatMap { $0.isEmpty ? nil : $0 })
                let tabSize = size(of: tab) + 1
                guard count < maximumTabs, total + spaceSize + tabSize <= maximumEncodedSize else {
                    isFull = true
                    break
                }
                space.tabs.append(tab)
                spaceSize += tabSize
                count += 1
            }
            if !space.tabs.isEmpty {
                fields.spaces.append(space)
                total += spaceSize
            }
        }
        return fields
    }
}
