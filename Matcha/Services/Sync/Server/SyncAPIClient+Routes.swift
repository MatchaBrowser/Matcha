import Foundation

/// Routes of the API v1 (`SYNC.md` § 4.2 to § 4.7).
extension SyncAPIClient {
    // MARK: Server and sessions

    func server() async throws -> SyncServerInfo {
        try await json("GET", "server", authenticated: false)
    }

    func prelogin(email: String) async throws -> SyncKDF {
        let response: SyncPreloginResponse = try await json(
            "POST",
            "auth/prelogin",
            body: SyncPreloginRequest(email: email),
            authenticated: false,
        )
        return response.kdf
    }

    func createAccount(_ request: SyncCreateAccountRequest) async throws -> SyncSessionResponse {
        try await json("POST", "accounts", body: request, authenticated: false)
    }

    func login(_ request: SyncLoginRequest) async throws -> SyncSessionResponse {
        try await json("POST", "auth/login", body: request, authenticated: false)
    }

    /// Revokes this device's tokens.
    func logout() async throws {
        try await call("POST", "auth/logout", authenticated: true)
    }

    func recoverStart(_ request: SyncRecoverStartRequest) async throws -> SyncRecoverStartResponse {
        try await json("POST", "auth/recover/start", body: request, authenticated: false)
    }

    func recoverFinish(_ request: SyncRecoverFinishRequest) async throws -> SyncSessionResponse {
        try await json("POST", "auth/recover/finish", body: request, authenticated: false)
    }

    // MARK: Account and devices

    func account() async throws -> SyncAccountDescription {
        try await json("GET", "account", authenticated: true)
    }

    func changePassword(_ request: SyncChangePasswordRequest) async throws {
        try await call("POST", "account/password", body: request, authenticated: true)
    }

    func changeRecovery(_ request: SyncChangeRecoveryRequest) async throws {
        try await call("POST", "account/recovery", body: request, authenticated: true)
    }

    func changeEmail(_ request: SyncChangeEmailRequest) async throws {
        try await call("POST", "account/email", body: request, authenticated: true)
    }

    func deleteAccount(authKey: Data) async throws {
        try await call("POST", "account/delete", body: SyncAuthKeyRequest(authKey: authKey), authenticated: true)
    }

    func devices() async throws -> [SyncDevice] {
        let response: SyncDevicesResponse = try await json("GET", "devices", authenticated: true)
        return response.devices
    }

    func renameDevice(_ id: UUID, to name: String) async throws {
        try await call("PATCH", "devices/\(id.uuidString)", body: SyncRenameDeviceRequest(name: name), authenticated: true)
    }

    func deleteDevice(_ id: UUID) async throws {
        try await call("DELETE", "devices/\(id.uuidString)", authenticated: true)
    }

    // MARK: Sync

    /// Changes written after `cursor`, by increasing version; `410 cursor_expired` becomes
    /// `SyncTransportError.cursorExpired`.
    func changes(since cursor: String?, limit: Int = 500) async throws -> SyncChangesResponse {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let cursor {
            query.append(URLQueryItem(name: "since", value: cursor))
        }
        do {
            return try await json("GET", "sync/changes", query: query, authenticated: true)
        } catch let error as SyncServerError where error.code == SyncServerError.cursorExpired {
            throw SyncTransportError.cursorExpired
        }
    }

    /// Sends an already encoded batch under its `Idempotency-Key`.
    func push(body: Data, key: UUID) async throws -> SyncPushResponse {
        var request = urlRequest("POST", "sync/push", body: body)
        request.setValue(key.uuidString, forHTTPHeaderField: "Idempotency-Key")
        let (data, _) = try await send(request, authenticated: true)
        do {
            return try SyncCoding.decoder().decode(SyncPushResponse.self, from: data)
        } catch {
            throw SyncClientError.unreadableAnswer
        }
    }

    /// Request of the event stream (`text/event-stream`), without its token.
    func eventsRequest() -> URLRequest {
        var request = urlRequest("GET", "sync/events")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        return request
    }

    // MARK: Avatar

    /// Uploads the encrypted avatar, replacing the previous one.
    func putAvatar(_ data: Data) async throws -> SyncAvatarDescription {
        let request = urlRequest("PUT", "account/avatar", body: data, contentType: "application/octet-stream")
        let (answer, _) = try await send(request, authenticated: true)
        return (try? SyncCoding.decoder().decode(SyncAvatarDescription.self, from: answer)) ?? SyncAvatarDescription()
    }

    /// The encrypted avatar, of at most `limit` bytes (`maxAvatarBytes`); nil without one.
    func avatar(limit: Int) async throws -> Data? {
        var request = urlRequest("GET", "account/avatar")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        do {
            return try await send(request, authenticated: true, limit: limit).0
        } catch let error as SyncServerError where error.status == 404 {
            return nil
        }
    }

    func deleteAvatar() async throws {
        try await call("DELETE", "account/avatar", authenticated: true)
    }

    // MARK: Packages

    func putBlob(_ data: Data, id: UUID) async throws {
        var request = urlRequest("PUT", "blobs/\(id.uuidString)", body: data, contentType: "application/octet-stream")
        request.setValue("*", forHTTPHeaderField: "If-None-Match")
        do {
            _ = try await send(request, authenticated: true)
        } catch let error as SyncServerError where error.code == SyncServerError.blobExists {
            throw SyncTransportError.blobExists
        }
    }

    /// The encrypted package `id`, of at most `limit` bytes (`maxBlobBytes`).
    func blob(id: UUID, limit: Int) async throws -> Data {
        var request = urlRequest("GET", "blobs/\(id.uuidString)")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        do {
            return try await send(request, authenticated: true, limit: limit).0
        } catch let error as SyncServerError where error.status == 404 {
            throw SyncTransportError.blobNotFound
        }
    }

    func deleteBlob(id: UUID) async throws {
        try await call("DELETE", "blobs/\(id.uuidString)", authenticated: true)
    }
}
