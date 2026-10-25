import AppKit
import CoreGraphics
import CryptoKit
import Foundation
import Observation
import OSLog
import SwiftData

/// Sync through a private server, as the app and its settings see it (`SYNC.md` § 3 to § 5): the account of this Mac,
/// and while it is signed in, the engine, its triggers and the server's event stream. Made once in `AppEnvironment`,
/// started with the main session. An answer that ends the session (revoked device, deleted account, unknown tokens)
/// stops sync and keeps this Mac's browsing data.
@MainActor
@Observable
final class SyncService {
    var configuration: SyncConfiguration
    /// Triggers of the running sync; nil when this Mac isn't signed in.
    private(set) var coordinator: SyncCoordinator?
    /// Question the user must answer for sync to go on (first sync, mass deletion…).
    var question: SyncQuestion?
    /// Recovery kit of the account just created: sync starts once it is saved.
    var pendingRecoveryKit: SyncRecoveryKit?
    /// Error of the last cycle, if it failed.
    var lastError: (any Error)?
    /// This Mac's time minus the server's, in seconds (warning beyond 10 minutes).
    private(set) var clockOffset: TimeInterval?
    /// Image of the account's avatar (JPEG or PNG), decrypted and kept in cache; nil without one.
    private(set) var avatar: Data?
    /// `avatar` decoded once, by the bounded decoder: it comes from any Mac of the account (review TR3); nil without one
    /// or if it can't be decoded.
    private(set) var avatarImage: CGImage?
    /// Last reading of the account's avatar on the server.
    @ObservationIgnored var avatarCheckedAt: Date?
    @ObservationIgnored let defaults: UserDefaults
    @ObservationIgnored let keychain: SyncKeychain
    @ObservationIgnored let extensions: ExtensionSyncAdapter?
    /// Today tabs of the other Macs, shown by the command bar and the History menu; nil: not kept (tests).
    @ObservationIgnored let otherMacs: OtherMacsTabs?
    /// Folder of the sync states, one file per server and account; nil: kept in memory (tests).
    @ObservationIgnored let directory: URL?
    @ObservationIgnored let apiSession: URLSession
    @ObservationIgnored var session: BrowserSession?
    @ObservationIgnored var client: SyncAPIClient?
    /// Data of this Mac as the running engine sees it.
    @ObservationIgnored var store: MatchaSyncStore?
    @ObservationIgnored var eventStream: SyncEventStream?
    /// Work of the signed-in account (server description, avatar): cancelled with it, never written to another
    /// account (review SY24).
    @ObservationIgnored var accountTasks: [Task<Void, Never>] = []
    /// Waits for the app's activation to start again after the keychain refused (locked at launch, review SY22).
    @ObservationIgnored var activationObserver: (any NSObjectProtocol)?
    /// Keys of `UserDefaults` whose change is a change of this Mac.
    @ObservationIgnored var watchedKeys = SyncedSettings.keys + [SiteZoomStore.defaultsKey, ExtensionStateStore.defaultsKey]

    /// Beyond this lead of this Mac's clock over the server's, nothing is sent (`SYNC.md` § 2.8).
    static let maximumClockLead: TimeInterval = 24 * 60 * 60
    /// Beyond this gap, the settings warn that this Mac's clock is off.
    static let clockWarningGap: TimeInterval = 10 * 60
    /// An unused sync state (old account, unreadable file set aside) is deleted after 60 days, the lifetime of a refresh
    /// token (`SYNC.md` § 5).
    static let unusedStateLifetime: TimeInterval = 60 * 24 * 60 * 60

    init(
        defaults: UserDefaults,
        keychain: SyncKeychain = SyncKeychain(),
        extensions: ExtensionSyncAdapter?,
        otherMacs: OtherMacsTabs? = nil,
        directory: URL?,
        apiSession: URLSession = SyncAPIClient.makeSession(),
    ) {
        self.defaults = defaults
        self.keychain = keychain
        self.apiSession = apiSession
        self.extensions = extensions
        self.otherMacs = otherMacs
        self.directory = directory
        configuration = SyncConfiguration.load(from: defaults)
        setAvatar(avatarCacheURL.flatMap { try? Data(contentsOf: $0) })
    }

    /// The avatar and its image, decoded once (`SyncService+Avatar`).
    func setAvatar(_ image: Data?) {
        avatar = image
        avatarImage = image.flatMap { BoundedImageDecoder.decode($0, limits: .avatar) }
    }

    /// Sync is on and this Mac is signed in.
    var isActive: Bool {
        coordinator != nil
    }

    /// The account's sync state on this Mac (clock in the future, refused records, full account…).
    var engineState: SyncState? {
        coordinator?.engine.state
    }

    // MARK: Launch

    /// Starts sync at launch if this Mac is signed in; a copy of another Mac signs out first. The states no longer
    /// used are cleaned up in any case (review SY35).
    func start(session: BrowserSession) {
        self.session = session
        let current = configuration.server.flatMap { server in configuration.accountID.flatMap { stateURL(server: server, accountID: $0) } }
        removeUnusedStates(keeping: current)
        guard configuration.mode == .privateServer, configuration.signedOutReason == nil, let server = configuration.server,
              let accountID = configuration.accountID
        else {
            return
        }
        do {
            let device = try deviceIdentity()
            guard !device.isNew else {
                // A copy of this Mac (or a new keychain): its tokens are never used, a new sign-in gives it its own.
                Logger.sync.notice("Copied Mac: signing in again")
                keychain.removeAccount(server: server, accountID: accountID, items: [.accessToken, .refreshToken])
                signOutLocally(reason: .copiedMac, deletesState: false)
                return
            }
            guard let credentials = try storedCredentials(server: server, accountID: accountID) else {
                signOutLocally(reason: .sessionExpired, deletesState: false)
                return
            }
            try activate(
                server: server,
                accountID: accountID,
                accountKey: credentials.accountKey,
                tokens: credentials.tokens,
                deviceID: device.id,
            )
        } catch {
            // Keychain locked or refused: an error, not a sign-out; sync tries again when the app becomes active.
            Logger.sync.error("Sync not started: \(error.logSummary, privacy: .public)")
            lastError = error
            startAgainOnActivation()
        }
    }

    // MARK: Running

    /// Starts the engine, its triggers and the event stream for this account.
    func activate(
        server: SyncServerAddress,
        accountID: UUID,
        accountKey: SymmetricKey,
        tokens: SyncRefreshResponse,
        deviceID: UUID,
    ) throws {
        guard let session else {
            return
        }
        deactivate()
        let keychain = keychain
        let store = SyncTokenStore(accessToken: tokens.accessToken, refreshToken: tokens.refreshToken) { renewed in
            try keychain.set(Data(renewed.refreshToken.utf8), for: .refreshToken, server: server, accountID: accountID)
            try keychain.set(Data(renewed.accessToken.utf8), for: .accessToken, server: server, accountID: accountID)
        }
        let client = try SyncAPIClient(address: server, session: apiSession, clientVersion: Self.clientVersion, tokens: store)
        self.client = client
        let info = configuration.serverInfo ?? SyncServerInfo(api: 1)
        let identifiers = SyncIdentifiers(accountKey: accountKey)
        let device = SyncDeviceDescription(id: deviceID, name: Self.deviceName)
        let localStore = MatchaSyncStore(
            session: session,
            defaults: defaults,
            identifiers: identifiers,
            extensions: extensions,
            device: device,
        )
        self.store = localStore
        // This account's extensions only (review SY11); the single file of earlier versions becomes its own.
        extensions?.synced.use(
            url: extensionsURL(server: server, accountID: accountID),
            legacy: directory?.appendingPathComponent("extensions.json"),
        )
        let engine = SyncEngine(
            store: localStore,
            transport: SyncServerTransport(client: client, accountKey: accountKey, server: info),
            identifiers: identifiers,
            file: SyncStateFile(url: stateURL(server: server, accountID: accountID)),
            deviceID: deviceID,
        )
        engine.chooseFirstSync = { [weak self] in await self?.askFirstSync() ?? .merge }
        engine.confirmMassDeletion = { [weak self] count in await self?.confirm(.massDeletion(count: count)) ?? false }
        engine.confirmRecreations = { [weak self] count in await self?.askRecreations(count) ?? .sendAgain }
        let coordinator = SyncCoordinator(engine: engine)
        coordinator.didFinishCycle = { [weak self] error in
            Task { await self?.cycleDidFinish(error) }
        }
        self.coordinator = coordinator
        refreshOtherMacs()
        coordinator.start(observing: session.container.mainContext, defaults: defaults, watchedKeys: watchedKeys)
        startEventStream(client: client, info: info)
        removeUnusedStates(keeping: stateURL(server: server, accountID: accountID))
        accountTasks.append(Task {
            await refreshServerInfo()
            await refreshAvatar()
        })
    }

    /// Stops the engine and the event stream; a running cycle is cancelled (its state is saved after each step).
    func deactivate() {
        stopWaitingForActivation()
        accountTasks.forEach { $0.cancel() }
        accountTasks = []
        coordinator?.stop()
        coordinator = nil
        store = nil
        refreshOtherMacs()
        eventStream?.stop()
        eventStream = nil
        client = nil
        question?.answerByDefault()
        question = nil
    }

    private func startEventStream(client: SyncAPIClient, info: SyncServerInfo) {
        guard info.hasEvents else {
            return
        }
        let stream = SyncEventStream(client: client)
        stream.onChanges = { [weak self] in
            self?.coordinator?.syncSoon(after: .milliseconds(300))
        }
        stream.onSessionEnded = { [weak self] error in
            self?.sessionEnded(error)
        }
        eventStream = stream
        stream.start()
    }

    /// The server's description, read again at each start (limits, events, packages).
    private func refreshServerInfo() async {
        guard let client, let info = try? await client.server(), info.api == 1, !Task.isCancelled, self.client === client else {
            return
        }
        let hadEvents = configuration.serverInfo?.hasEvents == true
        configuration.serverInfo = info
        configuration.save(to: defaults)
        if info.hasEvents, !hadEvents, eventStream == nil {
            startEventStream(client: client, info: info)
        }
    }

    /// After a cycle: an error that ends the session signs out, a server busy is retried when it says, and the clock
    /// gap is read again.
    private func cycleDidFinish(_ error: (any Error)?) async {
        lastError = error
        refreshOtherMacs()
        if let error = error as? SyncServerError {
            if error.endsSession {
                sessionEnded(error)
                return
            }
            if let wait = error.retryAfter {
                coordinator?.wait(until: .now.addingTimeInterval(wait))
            }
        }
        // Renewed tokens the keychain refused: written again (review SY4).
        await client?.tokens?.saveIfNeeded()
        clockOffset = await client?.clock.offset
        // No event announces a new avatar: it is read with the account, at most every 15 minutes (SYNC.md § 4.4).
        if avatarCheckedAt.map({ Date.now.timeIntervalSince($0) > 15 * 60 }) ?? true {
            await refreshAvatar()
        }
    }

    /// The server ended the session (`SYNC.md` § 5): revoked device (state kept to resume), deleted account (state
    /// deleted), unknown tokens.
    func sessionEnded(_ error: SyncServerError) {
        Logger.sync.notice("Sync session ended: \(error.code, privacy: .public)")
        if let server = configuration.server, let accountID = configuration.accountID {
            keychain.removeAccount(server: server, accountID: accountID)
        }
        switch error.code {
        case SyncServerError.accountDeleted:
            signOutLocally(reason: .accountDeleted, deletesState: true)
        case SyncServerError.deviceRevoked:
            signOutLocally(reason: .deviceRevoked, deletesState: false)
        default:
            signOutLocally(reason: .sessionExpired, deletesState: false)
        }
    }

    /// Stops sync on this Mac; its browsing data stays.
    func signOutLocally(reason: SyncConfiguration.SignedOutReason?, deletesState: Bool) {
        deactivate()
        if deletesState, let server = configuration.server, let accountID = configuration.accountID {
            SyncStateFile(url: stateURL(server: server, accountID: accountID)).delete()
            extensions?.synced.forget()
        } else {
            extensions?.synced.use(url: nil)
        }
        if let reason {
            configuration.signedOutReason = reason
        } else {
            configuration = SyncConfiguration()
        }
        forgetAvatar()
        configuration.save(to: defaults)
    }

    /// “Matcha-Client” header: “1.2.0 (128)”.
    static var clientVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(version) (\(build))"
    }
}
