import SwiftUI

/// The questions sync asks before going on (`SYNC.md` § 5), as an alert of the window: first sync with data on both
/// sides, mass deletion, records the server no longer knows. Closed without an answer, the safe one is taken (merge,
/// keep, send again).
struct SyncQuestionAlert: ViewModifier {
    @Environment(SyncService.self) private var sync

    func body(content: Content) -> some View {
        content.alert(
            title,
            isPresented: Binding { sync.question != nil } set: {
                if !$0 {
                    sync.question?.answerByDefault()
                    sync.question = nil
                }
            },
            presenting: sync.question,
        ) { question in
            switch question.kind {
            case .firstSync:
                Button("Merge", role: .cancel) { sync.answer(.firstSync(.merge)) }
                Button("Replace This Mac's Data") { sync.answer(.firstSync(.replaceLocal)) }
                Button("Replace Synced Data", role: .destructive) { sync.answer(.firstSync(.replaceRemote)) }
            case .massDeletion:
                Button("Keep Them", role: .cancel) { sync.answer(.massDeletion(confirmed: false)) }
                Button("Delete on All Macs", role: .destructive) { sync.answer(.massDeletion(confirmed: true)) }
            case .recreations:
                Button("Send Them Again", role: .cancel) { sync.answer(.recreations(.sendAgain)) }
                Button("Replace This Mac's Data", role: .destructive) { sync.answer(.recreations(.replaceLocal)) }
            }
        } message: { question in
            switch question.kind {
            case .firstSync:
                Text("""
                This Mac and your synced data each have their own Spaces and tabs. Merge keeps both; replacing keeps \
                only one side.
                """)
            case let .massDeletion(count):
                Text("Changes made on this Mac would delete \(count) items, more than half of your synced data, on all your Macs.")
            case let .recreations(count):
                Text("""
                The server no longer knows \(count) items of this Mac, maybe after a restore. Send them again, or take \
                what the server has.
                """)
            }
        }
    }

    private var title: Text {
        switch sync.question?.kind {
        case .massDeletion: Text("Delete these items on all your Macs?")
        case .recreations: Text("Send this Mac's items again?")
        case .firstSync, nil: Text("Your Macs already have data")
        }
    }
}

extension View {
    /// Asks the questions of sync in this window.
    func asksSyncQuestions() -> some View {
        modifier(SyncQuestionAlert())
    }
}
