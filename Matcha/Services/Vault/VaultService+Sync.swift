import Foundation
import OSLog

/// The vault in the sync cycle (`VAULT.md` § 5): after each complete read, it verifies what the server shows, takes it,
/// reconciles or repairs, then writes this Mac's edits in an atomic batch.
extension VaultService: SyncVaultParticipant {
    func syncDidActivate(_ account: SyncVaultAccount) {
        self.account = account
        file = VaultStateFile(url: account.stateURL)
        state = file.load()
        serverState = nil
        refreshStatus()
    }

    func syncDidDeactivate(forgetting: Bool) {
        lock()
        if forgetting {
            file.delete()
            state = VaultState()
        }
        account = nil
        serverState = nil
        refreshStatus()
    }

    func syncCycleDidFinish(state engineState: SyncState) async {
        serverState = engineState
        refreshStatus()
        guard session != nil else {
            // Locked: the verification waits for the unlock (`VAULT.md` § 5.2).
            return
        }
        await verifyAndWrite(engineState)
    }

    // MARK: Verify, then write

    /// Verifies the server's vault against the state, takes what succeeds, reconciles a divergence, repairs what the
    /// server lost, then sends this Mac's edits.
    func verifyAndWrite(_ engineState: SyncState) async {
        guard let session, let account, !isWriting else {
            return
        }
        isWriting = true
        defer { isWriting = false }
        let view = VaultServerView.read(from: engineState, vaultID: session.keys.vaultID, identifiers: account.identifiers)
        let verifier = VaultVerifier(keys: session.keys, identifiers: account.identifiers)
        let result = verifier.verify(view, state: state)
        var extraClock: [String: Int] = [:]
        switch result.outcome {
        case .accepted, .unchanged, .tampered, .incomplete, .empty:
            state = result.state
        case .unverifiable:
            state.notice = .waitingForAnotherMac
        case .divergent:
            guard let server = result.server,
                  let reconciliation = try? VaultReconciler(codec: session.codec, deviceID: account.deviceID).reconcile(state, with: server)
            else {
                break
            }
            state = reconciliation.state
            extraClock = reconciliation.clock
            state.notice = .completedFromThisMac
            Logger.vault.notice("Vault divergence: \(reconciliation.restored, privacy: .public) items restored from this Mac")
        }
        if result.outcome != .unverifiable, result.outcome != .divergent {
            state.notice = result.repairs.isEmpty ? (result.waiting.isEmpty ? nil : .itemsWaiting) : .completedFromThisMac
        }
        rebaseEdits(session: session)
        saveState()
        rebuildItems()
        await write(view: view, clock: extraClock)
        await repair(result.repairs, view: view)
        await deleteObsoleteBlobs()
    }

    /// The edits of this Mac made on a version that is no longer the one in force: merged with it (`VAULT.md` § 5.4).
    private func rebaseEdits(session: VaultSession) {
        for (id, edit) in state.edits {
            guard let current = state.items[id], current.isCited, current.digest != edit.base?.digest else {
                continue
            }
            guard let sealed = edit.sealed else {
                // Deleted here, changed there: the change wins (`VAULT.md` § 5.4).
                state.edits[id] = nil
                continue
            }
            do {
                let local = try session.codec.open(sealed, id: id)
                let remote = try session.codec.open(current.sealed, id: id)
                let base = try edit.base.map { try session.codec.open($0, id: id).content } ?? VaultItemContent()
                var merged = VaultMerge.merged(local: local.content, remote: remote.content, base: base)
                merged.overview.modifiedAt = later(than: [local.content.overview.modifiedAt, remote.content.overview.modifiedAt])
                merged.overview.modifiedBy = account?.deviceID
                let resealed = try session.codec.seal(merged, id: id, itemKey: remote.itemKey)
                state.edits[id] = VaultEdit(
                    sealed: resealed,
                    base: current.sealed,
                    modifiedAt: merged.overview.modifiedAt,
                    modifiedBy: merged.overview.modifiedBy,
                    trashedAt: merged.overview.trashedAt,
                    blobs: edit.blobs,
                )
            } catch {
                Logger.vault.error("Vault edit not merged: \(error.logSummary, privacy: .public)")
            }
        }
    }

    /// Now, or 1 ms after the latest of `dates`.
    func later(than dates: [Date?]) -> Date {
        let latest = dates.compactMap(\.self).max()
        guard let latest, latest >= now() else {
            return now()
        }
        return latest.addingTimeInterval(0.001)
    }
}
