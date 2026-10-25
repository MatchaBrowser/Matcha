import Foundation
@testable import Matcha
import Testing

/// The models of the API v1 read the examples of `SYNC.md` § 4 as the document writes them, and the requests leave
/// with the fields it names (review TS12). The document's `"…"` become valid values (base64, identifiers).
struct SyncAPIModelsTests {
    private static let accountID = "5D0C7A3E-2B1F-4E8D-9A6C-0F3B7E1D2C54"
    private static let deviceID = "3F2A8C1E-6B0D-4C5E-9F1A-2B7D8E4C6A10"
    private static let recordID = "7C4B2E9A-1D3F-4B6E-8A0C-5E2D9F1B3A76"

    private func decode<Value: Decodable>(_: Value.Type, _ json: String) throws -> Value {
        try SyncCoding.decoder().decode(Value.self, from: Data(json.utf8))
    }

    /// The top-level fields of `value` once encoded.
    private func fields(of value: some Encodable) throws -> Set<String> {
        let object = try JSONSerialization.jsonObject(with: SyncCoding.encoder().encode(value)) as? [String: Any]
        return try Set(#require(object).keys)
    }

    @Test func `the server description reads its limits and features`() throws {
        let info = try decode(SyncServerInfo.self, """
        {
            "api": 1,
            "software": "syncserver 0.1.0",
            "registration": "invitation",
            "limits": {
                "maxPayloadBytes": 262144,
                "maxChangesPerPush": 500,
                "maxRequestBytes": 4194304,
                "maxBlobBytes": 22020096,
                "maxAvatarBytes": 270336,
                "maxAccountBytes": null
            },
            "minimumIterations": 600000,
            "maximumIterations": 10000000,
            "features": ["events", "blobs", "avatar"]
        }
        """)
        #expect(info.api == 1)
        #expect(info.requiresInvitation)
        #expect(info.hasEvents && info.hasBlobs && info.hasAvatar)
        #expect(info.limits?.maxChangesPerPush == 500)
        #expect(info.limits?.maxAccountBytes == nil)
        #expect(info.maximumBlobBytes == 22_020_096)
        #expect(info.iterations == 600_000)
        // Only `api` is required: an older server's description still reads.
        #expect(try decode(SyncServerInfo.self, #"{ "api": 1 }"#).features == nil)
    }

    @Test func `a session, its key parameters and the recovery answers read`() throws {
        let session = try decode(SyncSessionResponse.self, """
        {
            "accountId": "\(Self.accountID)",
            "deviceId": "\(Self.deviceID)",
            "accessToken": "access",
            "refreshToken": "refresh",
            "expiresIn": 900,
            "wrappedAccountKey": "AAEC",
            "keyVersion": 1
        }
        """)
        #expect(session.accountId.uuidString == Self.accountID)
        #expect(session.deviceId.uuidString == Self.deviceID)
        #expect(session.wrappedAccountKey == Data([0, 1, 2]))
        #expect(session.expiresIn == 900)

        let prelogin = try decode(
            SyncPreloginResponse.self,
            #"{ "kdf": { "algorithm": "pbkdf2-sha256", "iterations": 600000, "salt": "q83vEjRWeJq83vEjRWeJqw==" } }"#,
        )
        #expect(prelogin.kdf.algorithm == SyncKDF.algorithmName)
        #expect(prelogin.kdf.salt.count == SyncKDF.saltLength)

        let refresh = try decode(SyncRefreshResponse.self, #"{ "accessToken": "a", "refreshToken": "r", "expiresIn": 900 }"#)
        #expect(refresh.refreshToken == "r")
        let recovery = try decode(
            SyncRecoverStartResponse.self,
            #"{ "recoveryToken": "t", "expiresIn": 600, "recoveryWrappedAccountKey": "AAEC" }"#,
        )
        #expect(recovery.recoveryWrappedAccountKey == Data([0, 1, 2]))
    }

    @Test func `the account and its devices read`() throws {
        let account = try decode(SyncAccountDescription.self, """
        {
            "accountId": "\(Self.accountID)",
            "email": "jeremy@example.com",
            "createdAt": "2026-10-17T08:30:12.401Z",
            "usage": { "records": 1843, "blobs": 2, "bytes": 524288 },
            "maxAccountBytes": null,
            "avatar": null
        }
        """)
        #expect(account.usage?.records == 1843)
        #expect(account.avatar == nil)
        #expect(account.createdAt.map(SyncCoding.string(from:)) == "2026-10-17T08:30:12.401Z")
        let withAvatar = try decode(SyncAccountDescription.self, """
        { "accountId": "\(Self.accountID)", "email": "jeremy@example.com", "avatar": { "size": 4096, "updatedAt": "2026-10-17T08:30:12Z" } }
        """)
        #expect(withAvatar.avatar?.size == 4096)

        let devices = try decode(SyncDevicesResponse.self, """
        {
            "devices": [
                {
                    "id": "\(Self.deviceID)",
                    "name": "MacBook Pro",
                    "createdAt": "2026-10-17T08:30:12.401Z",
                    "lastSeenAt": "2026-10-18T09:00:00Z",
                    "current": true
                }
            ]
        }
        """)
        #expect(devices.devices.map(\.name) == ["MacBook Pro"])
        #expect(devices.devices.first?.current == true)
    }

    @Test func `changes and push results read`() throws {
        let record = """
        { "id": "\(Self.recordID)", "version": 1843, "deleted": false, "keyVersion": 1, "payload": "AQ",
            "updatedAt": "2026-10-17T08:30:12.401Z" }
        """
        let changes = try decode(SyncChangesResponse.self, #"{ "changes": [\#(record)], "cursor": "c_1843", "hasMore": false }"#)
        #expect(changes.changes.map(\.version) == [1843])
        #expect(changes.cursor == "c_1843")

        let push = try decode(SyncPushResponse.self, """
        {
            "results": [
                { "id": "\(Self.recordID)", "status": "applied", "version": 1843 },
                { "id": "\(Self.recordID)", "status": "conflict", "current": \(record) },
                { "id": "\(Self.deviceID)", "status": "conflict", "current": null },
                { "id": "\(Self.accountID)", "status": "rejected", "code": "payload_too_large" }
            ]
        }
        """)
        #expect(push.results.map(\.status) == ["applied", "conflict", "conflict", "rejected"])
        #expect(push.results[0].version == 1843)
        #expect(push.results[1].current?.payload == "AQ")
        #expect(push.results[2].current == nil)
        #expect(push.results[3].code == SyncRejectionCode.payloadTooLarge)
    }

    @Test func `requests leave with the documented fields`() throws {
        let kdf = SyncKDF.random()
        let device = SyncDeviceDescription(id: UUID(), name: "MacBook Pro")
        let envelope = SyncKeyEnvelope(authKey: Data([1]), wrappedAccountKey: Data([2]))
        #expect(try fields(of: SyncCreateAccountRequest(
            email: "jeremy@example.com",
            invitation: "K7QD-2MXP",
            kdf: kdf,
            authKey: Data([1]),
            wrappedAccountKey: Data([2]),
            recovery: envelope,
            device: device,
        )) == ["email", "invitation", "kdf", "authKey", "wrappedAccountKey", "recovery", "device"])
        #expect(try fields(of: kdf) == ["algorithm", "iterations", "salt"])
        #expect(try fields(of: SyncLoginRequest(email: "a@example.com", authKey: Data([1]), device: device)) == [
            "email",
            "authKey",
            "device",
        ])
        #expect(try fields(of: SyncRecoverFinishRequest(
            recoveryToken: "t",
            kdf: kdf,
            authKey: Data([1]),
            wrappedAccountKey: Data([2]),
            recovery: nil,
            device: device,
        )) == ["recoveryToken", "kdf", "authKey", "wrappedAccountKey", "device"])
        #expect(try fields(of: SyncChangePasswordRequest(authKey: Data([1]), kdf: kdf, newAuthKey: Data([2]), wrappedAccountKey: Data([3])))
            == ["authKey", "kdf", "newAuthKey", "wrappedAccountKey"])
        #expect(try fields(of: SyncChangeRecoveryRequest(authKey: Data([1]), recovery: envelope)) == ["authKey", "recovery"])
        #expect(try fields(of: SyncChangeEmailRequest(authKey: Data([1]), email: "b@example.com")) == ["authKey", "email"])

        // A creation says `"baseVersion": null`, as the document writes it.
        let change = SyncServerChange(id: UUID(), baseVersion: nil, deleted: false, keyVersion: 1, payload: "AQ")
        let body = try #require(try String(bytes: SyncCoding.encoder().encode(SyncPushRequest(changes: [change])), encoding: .utf8))
        #expect(body.contains(#""baseVersion":null"#))
        #expect(try fields(of: change) == ["id", "baseVersion", "deleted", "keyVersion", "payload"])
    }
}
