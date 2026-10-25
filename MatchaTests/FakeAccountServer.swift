import Foundation
@testable import Matcha

/// A sync server for the account tests (review TS8), under `/api/v1` (`MockURLProtocol`): one account, its key
/// envelopes kept as the app sends them, its devices each with their own token, and the records pushed. Answers like
/// the reference server (`SYNC.md` § 4.8): `invalid_credentials` for a wrong key, `device_revoked` for the token of a
/// device disconnected, `account_deleted` once the account is gone. Nothing is decrypted: the server never could.
final class FakeAccountServer: @unchecked Sendable {
    private struct Account {
        var email: String
        var kdf: Any
        var authKey: String
        var wrappedAccountKey: String
        var recovery: [String: Any]
    }

    private let lock = NSLock()
    private var account: Account?
    /// Name of each device, by identifier; its token is `access-<identifier>`.
    private var devices: [String: String] = [:]
    /// Devices disconnected (revoked, or by a password change or a recovery), or of the deleted account.
    private var formerDevices: Set<String> = []
    private var recordCount = 0
    let accountID = UUID()

    var hasAccount: Bool {
        lock.withLock { account != nil }
    }

    var email: String? {
        lock.withLock { account?.email }
    }

    var deviceNames: [String: String] {
        lock.withLock { devices }
    }

    func handle(_ request: URLRequest, _ body: Data) throws -> MockResponse {
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
        let path = request.url?.path ?? ""
        switch (request.httpMethod ?? "", path) {
        case ("GET", "/api/v1/server"):
            return try MockURLProtocol.json(200, ["api": 1, "registration": "open", "features": [] as [String]])
        case ("POST", "/api/v1/accounts"):
            return try create(object)
        case ("POST", "/api/v1/auth/prelogin"):
            return try prelogin(object)
        case ("POST", "/api/v1/auth/login"):
            return try login(object)
        case ("POST", "/api/v1/auth/recover/start"):
            return try recoverStart(object)
        case ("POST", "/api/v1/auth/recover/finish"):
            return try recoverFinish(object)
        default:
            return try authenticated(request, path: path, object)
        }
    }

    // MARK: Without a session

    private func create(_ object: [String: Any]) throws -> MockResponse {
        lock.withLock {
            account = Account(
                email: object["email"] as? String ?? "",
                kdf: object["kdf"] ?? [:],
                authKey: object["authKey"] as? String ?? "",
                wrappedAccountKey: object["wrappedAccountKey"] as? String ?? "",
                recovery: object["recovery"] as? [String: Any] ?? [:],
            )
        }
        return try session(for: object, status: 201)
    }

    private func prelogin(_ object: [String: Any]) throws -> MockResponse {
        let kdf = lock.withLock { account?.email == object["email"] as? String ? account?.kdf : nil }
        return try MockURLProtocol.json(
            200,
            ["kdf": kdf ?? ["algorithm": "pbkdf2-sha256", "iterations": 600_000, "salt": "AAAAAAAAAAAAAAAAAAAAAA=="]],
        )
    }

    private func login(_ object: [String: Any]) throws -> MockResponse {
        let matches = lock.withLock { account?.email == object["email"] as? String && account?.authKey == object["authKey"] as? String }
        guard matches else {
            return MockURLProtocol.problem(401, "invalid_credentials")
        }
        return try session(for: object, status: 200)
    }

    private func recoverStart(_ object: [String: Any]) throws -> MockResponse {
        let wrapped = lock.withLock { () -> String? in
            guard let account, account.email == object["email"] as? String,
                  account.recovery["authKey"] as? String == object["recoveryAuthKey"] as? String
            else {
                return nil
            }
            return account.recovery["wrappedAccountKey"] as? String
        }
        guard let wrapped else {
            return MockURLProtocol.problem(401, "invalid_credentials")
        }
        return try MockURLProtocol.json(200, ["recoveryToken": "recovery", "expiresIn": 600, "recoveryWrappedAccountKey": wrapped])
    }

    private func recoverFinish(_ object: [String: Any]) throws -> MockResponse {
        guard object["recoveryToken"] as? String == "recovery" else {
            return MockURLProtocol.problem(401, "invalid_credentials")
        }
        lock.withLock {
            account?.kdf = object["kdf"] ?? [:]
            account?.authKey = object["authKey"] as? String ?? ""
            account?.wrappedAccountKey = object["wrappedAccountKey"] as? String ?? ""
            if let recovery = object["recovery"] as? [String: Any] {
                account?.recovery = recovery
            }
            // A recovery disconnects the other devices (`SYNC.md` § 3.7).
            disconnect { _ in true }
        }
        return try session(for: object, status: 200)
    }

    /// The session of the device described in `object`, which joins the account.
    private func session(for object: [String: Any], status: Int) throws -> MockResponse {
        let device = object["device"] as? [String: Any]
        let id = device?["id"] as? String ?? UUID().uuidString
        let wrapped = lock.withLock { () -> String in
            devices[id] = device?["name"] as? String ?? ""
            return account?.wrappedAccountKey ?? ""
        }
        return try MockURLProtocol.json(status, [
            "accountId": accountID.uuidString,
            "deviceId": id,
            "accessToken": "access-\(id)",
            "refreshToken": "refresh-\(id)",
            "expiresIn": 900,
            "wrappedAccountKey": wrapped,
            "keyVersion": 1,
        ])
    }

    // MARK: With a session

    private func authenticated(_ request: URLRequest, path: String, _ object: [String: Any]) throws -> MockResponse {
        let token = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer access-", with: "") ?? ""
        if let refusal = lock.withLock({ refusal(of: token) }) {
            return MockURLProtocol.problem(401, refusal)
        }
        let checksKey = ["/api/v1/account/password", "/api/v1/account/recovery", "/api/v1/account/email", "/api/v1/account/delete"]
        if checksKey.contains(path), lock.withLock({ account?.authKey != object["authKey"] as? String }) {
            return MockURLProtocol.problem(401, "invalid_credentials")
        }
        let method = request.httpMethod ?? ""
        if path.hasPrefix("/api/v1/account/") {
            return change(path, token: token, object)
        }
        if path.hasPrefix("/api/v1/devices") {
            return try devices(method, path, token: token, object)
        }
        switch (method, path) {
        case ("POST", "/api/v1/sync/push"):
            let changes = object["changes"] as? [[String: Any]] ?? []
            let results = lock.withLock { () -> [[String: Any]] in
                changes.map { change in
                    recordCount += 1
                    return ["id": change["id"] ?? "", "status": "applied", "version": recordCount]
                }
            }
            return try MockURLProtocol.json(200, ["results": results])
        case ("GET", "/api/v1/sync/changes"):
            return try MockURLProtocol.json(200, ["changes": [] as [Any], "cursor": "c_0", "hasMore": false])
        case ("POST", "/api/v1/auth/logout"):
            _ = lock.withLock { devices.removeValue(forKey: token) }
            return MockResponse(status: 204)
        default:
            return MockURLProtocol.problem(404, "not_found")
        }
    }

    /// `POST /v1/account/…`, its `authKey` already checked.
    private func change(_ path: String, token: String, _ object: [String: Any]) -> MockResponse {
        lock.withLock {
            switch path {
            case "/api/v1/account/password":
                account?.kdf = object["kdf"] ?? [:]
                account?.authKey = object["newAuthKey"] as? String ?? ""
                account?.wrappedAccountKey = object["wrappedAccountKey"] as? String ?? ""
                // The other devices are disconnected (`SYNC.md` § 3.6).
                disconnect { $0 != token }
            case "/api/v1/account/recovery":
                account?.recovery = object["recovery"] as? [String: Any] ?? [:]
            case "/api/v1/account/email":
                account?.email = object["email"] as? String ?? ""
            case "/api/v1/account/delete":
                account = nil
                disconnect { _ in true }
            default:
                return MockURLProtocol.problem(404, "not_found")
            }
            return MockResponse(status: 204)
        }
    }

    /// `GET /v1/devices`, `PATCH` and `DELETE /v1/devices/{id}`.
    private func devices(_ method: String, _ path: String, token: String, _ object: [String: Any]) throws -> MockResponse {
        let id = String(path.dropFirst("/api/v1/devices/".count))
        switch method {
        case "GET":
            let list = lock.withLock { devices.map { ["id": $0.key, "name": $0.value, "current": $0.key == token] } }
            return try MockURLProtocol.json(200, ["devices": list])
        case "PATCH":
            lock.withLock { devices[id] = object["name"] as? String ?? "" }
        case "DELETE":
            lock.withLock { disconnect { $0 == id } }
        default:
            return MockURLProtocol.problem(404, "not_found")
        }
        return MockResponse(status: 204)
    }

    /// Why the token of `device` is refused, under the lock; nil when it is valid.
    private func refusal(of device: String) -> String? {
        if devices[device] != nil, account != nil {
            return nil
        }
        guard formerDevices.contains(device) else {
            return "invalid_token"
        }
        return account == nil ? "account_deleted" : "device_revoked"
    }

    /// Revokes the tokens of the devices chosen, under the lock.
    private func disconnect(_ isChosen: (String) -> Bool) {
        for id in devices.keys where isChosen(id) {
            devices[id] = nil
            formerDevices.insert(id)
        }
    }
}
