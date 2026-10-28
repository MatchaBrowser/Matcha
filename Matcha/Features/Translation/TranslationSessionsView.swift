import SwiftUI
import Translation

/// Hidden views of a window's translation sessions (task 9.3), one per language pair of its `TranslationHost`: each
/// gets a session from `translationTask` and runs the jobs of its pair. macOS asks there, over the window, to
/// download languages that are missing.
struct TranslationSessionsView: View {
    let host: TranslationHost

    var body: some View {
        ZStack {
            ForEach(host.pairs) { pair in
                Color.clear
                    .translationTask(host.configurations[pair]) { @concurrent session in
                        await TranslationSessionWorker.run(pair, session: session, host: host)
                    }
            }
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }
}

/// Runs the jobs of a pair with its session, off the main actor: the session is not `Sendable` and never leaves
/// this task (`SessionTextTranslator`).
nonisolated enum TranslationSessionWorker {
    @concurrent static func run(_ pair: TranslationHost.Pair, session: TranslationSession, host: TranslationHost) async {
        let translator = PageBlockTranslator(translator: SessionTextTranslator(session: session), method: .preferred())
        while let job = await host.takeJob(for: pair) {
            do {
                try await job.continuation.resume(returning: translator.translate(job.blocks))
            } catch {
                job.continuation.resume(throwing: error)
            }
        }
        await host.sessionDidEnd(for: pair)
    }
}
