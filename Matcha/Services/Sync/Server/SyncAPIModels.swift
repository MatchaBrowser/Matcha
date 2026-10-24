import Foundation

// Bodies of the sync server's API v1 (`SYNC.md` § 4): binary data in standard base 64 (`Data`), dates in ISO 8601
// to the millisecond. Unknown fields are ignored.

/// `GET /v1/server`.
nonisolated struct SyncServerInfo: Codable, Equatable, Sendable {
    struct Limits: Codable, Equatable, Sendable {
        var maxPayloadBytes: Int?
        var maxChangesPerPush: Int?
        var maxRequestBytes: Int?
        var maxBlobBytes: Int?
        var maxAvatarBytes: Int?
        var maxAccountBytes: Int?
    }

    var api: Int
    var software: String?
    /// `open`, `invitation` or `closed`.
    var registration: String?
    var limits: Limits?
    var minimumIterations: Int?
    var maximumIterations: Int?
    var features: [String]?

    var requiresInvitation: Bool {
        registration == "invitation"
    }

    var isRegistrationClosed: Bool {
        registration == "closed"
    }

    var hasEvents: Bool {
        features?.contains("events") == true
    }

    var hasBlobs: Bool {
        features?.contains("blobs") == true
    }

    /// The server keeps the account's avatar (`SYNC.md` § 4.4); without it, the avatar setting is hidden.
    var hasAvatar: Bool {
        features?.contains("avatar") == true
    }

    /// Largest image of an avatar: the encrypted size allowed, less the padding and the encryption's overhead.
    var maximumAvatarImageBytes: Int {
        min(256 * 1024, (limits?.maxAvatarBytes ?? 270_336) - SyncCrypto.avatarPadding - 29)
    }

    /// Iterations used for a new account or password: this Matcha's minimum, raised to the server's if it asks for
    /// more (within this Matcha's bounds).
    var iterations: Int {
        min(max(minimumIterations ?? SyncKDF.minimumIterations, SyncKDF.minimumIterations), SyncKDF.maximumIterations)
    }
}

/// A checked server: its normalized address and its description.
nonisolated struct SyncServerEndpoint: Equatable, Sendable {
    let address: SyncServerAddress
    let info: SyncServerInfo
}

/// This Mac, as the server knows it.
nonisolated struct SyncDeviceDescription: Codable, Equatable, Sendable {
    var id: UUID
    var name: String
}

/// Account key wrapped by another key, and the key that proves it is known.
nonisolated struct SyncKeyEnvelope: Codable, Equatable, Sendable {
    var authKey: Data
    var wrappedAccountKey: Data
}

/// Answer of the routes that open a session (`SYNC.md` § 4.3).
nonisolated struct SyncSessionResponse: Codable, Equatable, Sendable {
    var accountId: UUID
    var deviceId: UUID
    var accessToken: String
    var refreshToken: String
    var expiresIn: Int?
    var wrappedAccountKey: Data
    var keyVersion: Int?
}

nonisolated struct SyncPreloginRequest: Codable, Sendable {
    var email: String
}

nonisolated struct SyncPreloginResponse: Codable, Sendable {
    var kdf: SyncKDF
}

nonisolated struct SyncCreateAccountRequest: Codable, Sendable {
    var email: String
    var invitation: String?
    var kdf: SyncKDF
    var authKey: Data
    var wrappedAccountKey: Data
    var recovery: SyncKeyEnvelope
    var device: SyncDeviceDescription
}

nonisolated struct SyncLoginRequest: Codable, Sendable {
    var email: String
    var authKey: Data
    var device: SyncDeviceDescription
}

nonisolated struct SyncRefreshRequest: Codable, Sendable {
    var refreshToken: String
}

nonisolated struct SyncRefreshResponse: Codable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresIn: Int?
}

nonisolated struct SyncRecoverStartRequest: Codable, Sendable {
    var email: String
    var recoveryAuthKey: Data
}

nonisolated struct SyncRecoverStartResponse: Codable, Sendable {
    var recoveryToken: String
    var expiresIn: Int?
    var recoveryWrappedAccountKey: Data
}

nonisolated struct SyncRecoverFinishRequest: Codable, Sendable {
    var recoveryToken: String
    var kdf: SyncKDF
    var authKey: Data
    var wrappedAccountKey: Data
    var recovery: SyncKeyEnvelope?
    var device: SyncDeviceDescription
}

/// `GET /v1/account`.
nonisolated struct SyncAccountDescription: Codable, Equatable, Sendable {
    struct Usage: Codable, Equatable, Sendable {
        var records: Int?
        var blobs: Int?
        var bytes: Int?
    }

    var accountId: UUID
    var email: String
    var createdAt: Date?
    var usage: Usage?
    var maxAccountBytes: Int?
    /// The account's avatar; nil without one.
    var avatar: SyncAvatarDescription?
}

/// Size and date of the account's encrypted avatar (`SYNC.md` § 4.4).
nonisolated struct SyncAvatarDescription: Codable, Equatable, Sendable {
    var size: Int?
    var updatedAt: Date?
}

nonisolated struct SyncChangePasswordRequest: Codable, Sendable {
    var authKey: Data
    var kdf: SyncKDF
    var newAuthKey: Data
    var wrappedAccountKey: Data
}

nonisolated struct SyncChangeRecoveryRequest: Codable, Sendable {
    var authKey: Data
    var recovery: SyncKeyEnvelope
}

nonisolated struct SyncChangeEmailRequest: Codable, Sendable {
    var authKey: Data
    var email: String
}

nonisolated struct SyncAuthKeyRequest: Codable, Sendable {
    var authKey: Data
}

/// A device of the account (`GET /v1/devices`).
nonisolated struct SyncDevice: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var createdAt: Date?
    var lastSeenAt: Date?
    var current: Bool?
}

nonisolated struct SyncDevicesResponse: Codable, Sendable {
    var devices: [SyncDevice]
}

nonisolated struct SyncRenameDeviceRequest: Codable, Sendable {
    var name: String
}

/// A record as the server stores it: its content encrypted (`SYNC.md` § 4.6).
nonisolated struct SyncServerRecord: Codable, Equatable, Sendable {
    var id: UUID
    var version: Int
    var deleted: Bool?
    var keyVersion: Int?
    var payload: String
    var updatedAt: Date?
}

nonisolated struct SyncChangesResponse: Codable, Sendable {
    var changes: [SyncServerRecord]
    var cursor: String
    var hasMore: Bool
}

/// A sent change; `baseVersion` is written as `null` for a creation.
nonisolated struct SyncServerChange: Codable, Equatable, Sendable {
    var id: UUID
    var baseVersion: Int?
    var deleted: Bool
    var keyVersion: Int
    var payload: String

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(baseVersion, forKey: .baseVersion)
        try container.encode(deleted, forKey: .deleted)
        try container.encode(keyVersion, forKey: .keyVersion)
        try container.encode(payload, forKey: .payload)
    }
}

nonisolated struct SyncPushRequest: Codable, Sendable {
    var changes: [SyncServerChange]
}

nonisolated struct SyncServerPushResult: Codable, Sendable {
    var id: UUID?
    /// `applied`, `conflict` or `rejected`.
    var status: String
    var version: Int?
    var current: SyncServerRecord?
    var code: String?
}

nonisolated struct SyncPushResponse: Codable, Sendable {
    var results: [SyncServerPushResult]
}
