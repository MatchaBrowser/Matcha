import AppKit
import Foundation
@testable import Matcha
import Testing

/// Notes in the command bar (task 12.7): found by their title or their text, ranked and opened in a tab; the actions
/// New Note, Note for This Page and Show All Notes; nothing in a private window.
@MainActor
@Suite(.webKit)
struct NotesCommandBarTests {
    private let session: BrowserSession
    private let windowModel: WindowModel
    private let context = CommandContext(isPrivate: false, showsSearchSuggestions: false)

    init() throws {
        session = try BrowserSession(container: BrowserSchema.makeContainer(inMemory: true))
        windowModel = WindowModel(session: session, defaults: nil)
    }

    private var profile: UUID? {
        windowModel.space.record.profile?.id
    }

    private func notes(_ text: String, context: CommandContext? = nil) async -> [CommandCandidate] {
        await NotesProvider(windowModel: windowModel).candidates(for: query(text), context: context ?? self.context)
    }

    @Test func `notes are found by their title or their text`() async throws {
        let trip = try #require(session.notes.createNote(profileID: profile, title: "Trip to Lyon"))
        let recipe = try #require(session.notes.createNote(profileID: profile, title: "Recipe"))
        session.notes.setContent(
            "[{\"type\": \"paragraph\", \"content\": [{\"type\": \"text\", \"text\": \"Lyon bakery\"}]}]",
            of: recipe.id,
        )
        _ = session.notes.createNote(profileID: UUID(), title: "Lyon elsewhere")

        let found = await notes("lyon")
        #expect(Set(found.compactMap { NoteTab.noteID(in: $0.url) }) == [trip.id, recipe.id])
        #expect(await notes("paris").isEmpty)
        #expect(await notes("lyon", context: CommandContext(isPrivate: true)).isEmpty)
    }

    @Test func `a note is ranked and opens in a tab`() throws {
        let id = UUID()
        let url = try #require(NoteTab.url(for: id))
        let byText = CommandCandidate(kind: .note(modifiedAt: .now, keywords: ["bakery"]), title: "Recipe", url: url)
        let rows = CommandRanker().rank(query("bakery"), candidates: [byText], now: .now)
        let row = try #require(rows.first { $0.style == .note })
        #expect(row.title == "Recipe")
        #expect(row.target == .open(url))

        let many = (0 ..< 6).compactMap { index in
            NoteTab.url(for: UUID()).map {
                CommandCandidate(kind: .note(modifiedAt: .now, keywords: ["plan"]), title: "Plan \(index)", url: $0)
            }
        }
        #expect(CommandRanker().rank(query("plan"), candidates: many, now: .now).count { $0.style == .note } == CommandRanker.Limits()
            .notes)
    }

    @Test func `the note actions are offered, the page's only on a website`() {
        let actions = ActionsProvider(windowModel: windowModel).available(in: context).compactMap { candidate in
            if case let .action(action, _) = candidate.kind {
                return action
            }
            return nil
        }
        #expect(actions.contains(.newNote))
        #expect(actions.contains(.showAllNotes))
        #expect(!actions.contains(.pageNote))
        let privateActions = ActionsProvider(windowModel: windowModel).available(in: CommandContext(isPrivate: true))
        #expect(!privateActions.contains { $0.id == "action:newNote" })
    }

    @Test func `the note actions open a new note, the library and the panel`() throws {
        let model = CommandBarModel(windowModel: windowModel, suggestions: FakeSuggestionEngine().provider())
        var openedLibrary = false
        var executor = CommandBarExecutor(model: model, window: nil, openSettings: {})
        executor.openNotesLibrary = { openedLibrary = true }
        executor.animate = { $0() }

        let tab = try #require(executor.perform(.run(.perform(.newNote), mode: .newTab)))
        let note = try #require(session.notes.notes.first)
        #expect(tab.noteID == note.id)
        #expect(note.profileID == profile)
        #expect(tab.webView == nil)

        executor.perform(.run(.perform(.showAllNotes), mode: .newTab))
        #expect(openedLibrary)
        executor.perform(.run(.perform(.pageNote), mode: .newTab))
        #expect(windowModel.notesPanel.isOpen)
    }
}
