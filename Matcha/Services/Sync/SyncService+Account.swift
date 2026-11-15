import CryptoKit
import Foundation
import OSLog

/// The sync account (`SYNC.md` § 3.3 to § 3.7 and § 4.3 to § 4.5): server check, account creation, sign-in and
/// sign-out, forgotten password, password, recovery key and identifier changes, deletion, devices. The master password
/// and the recovery key never leave these calls; the master key is derived off the main thread. The Secret Key is
/// kept in the keychain with the account key.
extension SyncService {
    /// Checks the typed address: a server of the API v1 at that address, or under `/api` (the reference server).
    func checkServer(_ text: String) async throws -> SyncServerEndpoint {
        let address = try SyncServerAddress.parse(text).get()
        do {
            return try await SyncServerEndpoint(address: address, info: describe(address))
        } catch {
            guard let nested = try? SyncServerAddress.parse(address.normalized + "/api").get(),
                  let info = try? await describe(nested)
            else {
                throw error
            }
            return SyncServerEndpoint(address: nested, info: info)
        }
    }

    private func describe(_ address: SyncServerAddress) async throws -> SyncServerInfo {
        let client = try SyncAPIClient(address: address, session: apiSession, clientVersion: Self.clientVersion)
        let info: SyncServerInfo
        do {
            info = try await client.server()
        } catch let error as SyncServerError where error.status == 404 {
            throw SyncClientError.notASyncServer
        } catch SyncClientError.unreadableAnswer {
            throw SyncClientError.notASyncServer
        }
        guard info.api == 1 else {
            throw SyncClientError.notASyncServer
        }
        return info
    }

    /// Creates the account; sync starts once the returned recovery kit is saved (`recoveryKitSaved`).
    func createAccount(
        on endpoint: SyncServerEndpoint,
        email: String,
        password: String,
        invitation: String?,
    ) async throws -> SyncRecoveryKit {
        let email = SyncConfiguration.normalizedEmail(email)
        let server = endpoint.address
        let client = try SyncAPIClient(address: server, session: apiSession, clientVersion: Self.clientVersion)
        let iterations = endpoint.info.iterations
        let creation = try await Self.derive { try SyncAccountKeys.creation(password: password, iterations: iterations) }
        let device = try deviceIdentity()
        let response = try await client.createAccount(SyncCreateAccountRequest(
            email: email,
            invitation: invitation?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            kdf: creation.kdf,
            authKey: creation.authKey,
            wrappedAccountKey: creation.wrappedAccountKey,
            wrappedVaultRootKey: creation.wrappedVaultRootKey,
            recovery: SyncKeyEnvelope(
                authKey: creation.recoveryAuthKey,
                wrappedAccountKey: creation.recoveryWrappedAccountKey,
                wrappedVaultRootKey: creation.recoveryWrappedVaultRootKey,
            ),
            device: SyncDeviceDescription(id: device.id, name: Self.deviceName),
        ))
        try keep(response, keys: (creation.accountKey, creation.secretKey), endpoint: endpoint, email: email, deviceID: device.id)
        // Drawn here: nothing to check.
        try storeVaultEnvelope(creation.wrappedVaultRootKey, kdf: creation.kdf, server: server, accountID: response.accountId)
        let vaultRootKey = creation.vaultRootKey
        let kit = SyncRecoveryKit(
            server: server,
            email: email,
            secretKey: creation.secretKey.displayed,
            recoveryKey: creation.recoveryKey.displayed,
        )
        awaitSaving(kit)
        vaultRootKeyArrived(vaultRootKey)
        return kit
    }

    /// The kit of a new recovery key, kept until it is saved, and noted across launches (review SY12).
    func awaitSaving(_ kit: SyncRecoveryKit) {
        pendingRecoveryKit = kit
        configuration.isRecoveryKitUnsaved = true
        configuration.save(to: defaults)
    }

    /// The recovery kit is saved: sync starts if it wasn't running (a keychain error is shown as the last error).
    func recoveryKitSaved() {
        pendingRecoveryKit = nil
        configuration.isRecoveryKitUnsaved = false
        configuration.save(to: defaults)
        guard !isActive else {
            return
        }
        do {
            try startSignedIn()
        } catch {
            lastError = error
        }
    }

    /// Signs in to an existing account with its password and Secret Key (`SYNC.md` § 3.4); a reconnection to the same
    /// account resumes its sync state.
    func signIn(on endpoint: SyncServerEndpoint, email: String, password: String, secretKey: SyncSecretKey) async throws {
        let email = SyncConfiguration.normalizedEmail(email)
        let client = try SyncAPIClient(address: endpoint.address, session: apiSession, clientVersion: Self.clientVersion)
        let kdf = try await client.prelogin(email: email)
        let keys = try await Self.derive { try SyncAccountKeys.passwordKeys(password: password, secretKey: secretKey, kdf: kdf) }
        let device = try deviceIdentity()
        let response = try await client.login(SyncLoginRequest(
            email: email,
            authKey: Self.bytes(keys.authKey),
            device: SyncDeviceDescription(id: device.id, name: Self.deviceName),
        ))
        let accountKey = try Self.unwrap(response.wrappedAccountKey, with: keys.wrapKey)
        try keep(response, keys: (accountKey, secretKey), endpoint: endpoint, email: email, deviceID: device.id)
        let vaultRootKey = try keepVaultEnvelope(
            response.wrappedVaultRootKey,
            kdf: kdf,
            wrapKey: keys.wrapKey,
            server: endpoint.address,
            accountID: response.accountId,
        )
        try startSignedIn()
        vaultRootKeyArrived(vaultRootKey)
    }

    /// Signs out: this Mac's tokens are revoked on the server (when it answers), sync stops, the browsing data stays,
    /// and the sync state is deleted (a later sign-in is a first sync).
    func signOut() async {
        await withdrawDeviceTabs()
        // Nothing of this account runs while its tokens are revoked (review SY24).
        let client = client
        deactivate()
        if let client {
            try? await client.logout()
        }
        if let server = configuration.server, let accountID = configuration.accountID {
            keychain.removeAccount(server: server, accountID: accountID)
        }
        signOutLocally(reason: nil, deletesState: true)
    }

    // MARK: Forgotten password

    /// Recovers the account with its recovery key and a new master password (`SYNC.md` § 3.7); the other devices are
    /// disconnected. A new Secret Key is always drawn: the old one may have been lost, or left with a stolen Mac. The
    /// returned kit, to save, has it, and the recovery key typed, or a new one with `newRecoveryKey`.
    func recover(
        on endpoint: SyncServerEndpoint,
        email: String,
        recoveryKey: SyncRecoveryKey,
        newPassword: String,
        newRecoveryKey: Bool,
    ) async throws -> SyncRecoveryKit {
        let email = SyncConfiguration.normalizedEmail(email)
        let server = endpoint.address
        let client = try SyncAPIClient(address: server, session: apiSession, clientVersion: Self.clientVersion)
        let recovery = SyncAccountKeys.recoveryKeys(recoveryKey)
        let started = try await client.recoverStart(SyncRecoverStartRequest(email: email, recoveryAuthKey: Self.bytes(recovery.authKey)))
        let accountKey = try Self.unwrap(started.recoveryWrappedAccountKey, with: recovery.wrapKey)
        let vaultRootKey = try started.recoveryWrappedVaultRootKey.map { try Self.unwrapVault($0, with: recovery.wrapKey) }
        let kdf = SyncKDF.random(iterations: endpoint.info.iterations)
        let secretKey = SyncSecretKey.random()
        let keys = try await Self.derive { try SyncAccountKeys.passwordKeys(password: newPassword, secretKey: secretKey, kdf: kdf) }
        let replacement = newRecoveryKey ? SyncRecoveryKey.random() : nil
        let device = try deviceIdentity()
        let response = try await client.recoverFinish(SyncRecoverFinishRequest(
            recoveryToken: started.recoveryToken,
            kdf: kdf,
            authKey: Self.bytes(keys.authKey),
            wrappedAccountKey: SyncAccountKeys.wrap(accountKey, with: keys.wrapKey),
            wrappedVaultRootKey: vaultRootKey.map { try VaultCrypto.wrapRootKey($0, with: keys.wrapKey) },
            recovery: replacement.map { try Self.envelope(of: (accountKey, vaultRootKey), for: $0) },
            device: SyncDeviceDescription(id: device.id, name: Self.deviceName),
        ))
        try keep(response, keys: (accountKey, secretKey), endpoint: endpoint, email: email, deviceID: device.id)
        _ = try keepVaultEnvelope(
            response.wrappedVaultRootKey,
            kdf: kdf,
            wrapKey: keys.wrapKey,
            server: server,
            accountID: response.accountId,
        )
        try startSignedIn()
        vaultRootKeyArrived(vaultRootKey)
        let kit = SyncRecoveryKit(
            server: server,
            email: email,
            secretKey: secretKey.displayed,
            recoveryKey: (replacement ?? recoveryKey).displayed,
        )
        awaitSaving(kit)
        return kit
    }

    // MARK: Account changes

    /// Changes the master password (`SYNC.md` § 3.6): only the account key is wrapped again, the Secret Key stays; the
    /// other devices are disconnected and ask for the new password.
    func changePassword(current: String, new: String) async throws {
        let (client, accountKey) = try signedInAccount()
        let secretKey = try storedSecretKey()
        let currentKeys = try await currentKeys(password: current, client: client)
        // Wrapped again with the account key, or nothing changes (`VAULT.md` § 2.2).
        let vaultRootKey = try storedVaultRootKey(wrapKey: currentKeys.wrapKey)
        let kdf = SyncKDF.random(iterations: configuration.serverInfo?.iterations ?? SyncKDF.minimumIterations)
        let keys = try await Self.derive { try SyncAccountKeys.passwordKeys(password: new, secretKey: secretKey, kdf: kdf) }
        let wrappedVaultRootKey = try vaultRootKey.map { try VaultCrypto.wrapRootKey($0, with: keys.wrapKey) }
        try await client.changePassword(SyncChangePasswordRequest(
            authKey: Self.bytes(currentKeys.authKey),
            kdf: kdf,
            newAuthKey: Self.bytes(keys.authKey),
            wrappedAccountKey: SyncAccountKeys.wrap(accountKey, with: keys.wrapKey),
            wrappedVaultRootKey: wrappedVaultRootKey,
        ))
        if let server = configuration.server, let accountID = configuration.accountID {
            _ = try keepVaultEnvelope(wrappedVaultRootKey, kdf: kdf, wrapKey: keys.wrapKey, server: server, accountID: accountID)
        }
    }

    /// Replaces the recovery key; returns the new kit to save, with the same Secret Key (`SYNC.md` § 3.3): the way to
    /// get the Secret Key again for a new Mac.
    func replaceRecoveryKey(password: String) async throws -> SyncRecoveryKit {
        let (client, accountKey) = try signedInAccount()
        let secretKey = try storedSecretKey()
        let currentKeys = try await currentKeys(password: password, client: client)
        let vaultRootKey = try storedVaultRootKey(wrapKey: currentKeys.wrapKey)
        let recoveryKey = SyncRecoveryKey.random()
        try await client.changeRecovery(SyncChangeRecoveryRequest(
            authKey: Self.bytes(currentKeys.authKey),
            recovery: Self.envelope(of: (accountKey, vaultRootKey), for: recoveryKey),
        ))
        guard let server = configuration.server, let email = configuration.email else {
            throw SyncClientError.signedOut
        }
        let kit = SyncRecoveryKit(server: server, email: email, secretKey: secretKey.displayed, recoveryKey: recoveryKey.displayed)
        awaitSaving(kit)
        return kit
    }

    /// Changes the account's identifier; the devices stay signed in. The recovery kit names it: a new one should be
    /// saved (`replaceRecoveryKey`).
    func changeEmail(password: String, to email: String) async throws {
        let (client, _) = try signedInAccount()
        let authKey = try await currentAuthKey(password: password, client: client)
        let email = SyncConfiguration.normalizedEmail(email)
        try await client.changeEmail(SyncChangeEmailRequest(authKey: authKey, email: email))
        configuration.email = email
        configuration.save(to: defaults)
    }

    /// Deletes the account and all its data on the server; this Mac keeps its browsing data.
    func deleteAccount(password: String) async throws {
        let (client, _) = try signedInAccount()
        let authKey = try await currentAuthKey(password: password, client: client)
        try await client.deleteAccount(authKey: authKey)
        if let server = configuration.server, let accountID = configuration.accountID {
            keychain.removeAccount(server: server, accountID: accountID)
        }
        signOutLocally(reason: nil, deletesState: true)
    }

    // MARK: Devices

    func devices() async throws -> [SyncDevice] {
        try await signedInAccount().client.devices()
    }

    func renameDevice(_ id: UUID, to name: String) async throws {
        try await signedInAccount().client.renameDevice(id, to: name)
    }

    /// Disconnects a device: its tokens are revoked, it keeps its data, its tabs are no longer shown on the other Macs.
    func revokeDevice(_ id: UUID) async throws {
        try await signedInAccount().client.deleteDevice(id)
        forgetDeviceTabs(of: id)
    }

    // MARK: Helpers

    /// Keeps the session of `response`: account key, Secret Key and tokens in the keychain, the account in the
    /// configuration. The device is the one this Mac drew (`deviceID`, `SYNC.md` § 2.7): a session for another one is
    /// refused, the server can't give this Mac another device's identity (review SY19).
    private func keep(
        _ response: SyncSessionResponse,
        keys: (account: SymmetricKey, secret: SyncSecretKey),
        endpoint: SyncServerEndpoint,
        email: String,
        deviceID: UUID,
    ) throws {
        guard response.deviceId == deviceID else {
            Logger.sync.error("Session for another device: refused")
            throw SyncClientError.unreadableAnswer
        }
        let (server, accountID) = (endpoint.address, response.accountId)
        try keychain.set(Self.bytes(keys.account), for: .accountKey, server: server, accountID: accountID)
        try keepSecretKey(keys.secret, server: server, accountID: accountID)
        try keychain.set(Data(response.accessToken.utf8), for: .accessToken, server: server, accountID: accountID)
        try keychain.set(Data(response.refreshToken.utf8), for: .refreshToken, server: server, accountID: accountID)
        configuration = SyncConfiguration()
        configuration.mode = .privateServer
        configuration.server = server
        configuration.accountID = accountID
        configuration.email = email
        configuration.serverInfo = endpoint.info
        configuration.save(to: defaults)
    }

    /// Starts sync with the account kept in the keychain.
    private func startSignedIn() throws {
        guard let server = configuration.server, let accountID = configuration.accountID,
              let credentials = try storedCredentials(server: server, accountID: accountID)
        else {
            throw SyncClientError.signedOut
        }
        try activate(
            server: server,
            accountID: accountID,
            accountKey: credentials.accountKey,
            tokens: credentials.tokens,
            deviceID: deviceIdentity().id,
        )
    }

    /// Client and account key of the signed-in account.
    func signedInAccount() throws -> (client: SyncAPIClient, accountKey: SymmetricKey) {
        guard let client, let server = configuration.server, let accountID = configuration.accountID,
              let accountKey = try keychain.data(for: .accountKey, server: server, accountID: accountID)
        else {
            throw SyncClientError.signedOut
        }
        return (client, SymmetricKey(data: accountKey))
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
