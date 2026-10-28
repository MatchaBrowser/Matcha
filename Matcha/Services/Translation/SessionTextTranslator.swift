import Foundation
import Translation

/// `TranslationSession` as the translator of a page (task 9.1): plain texts in one batch per call, each answer found by
/// the identifier of its request (the order of a batch's answers is not promised); rich texts one at a time.
///
/// The session is not `Sendable` and its methods run off any actor: it never leaves the task that received it (the
/// `@concurrent` closure of `translationTask`, or the function that made it), and this translator, made in that task,
/// calls it from `@concurrent` methods. Only blocks and texts (`Sendable`) cross to the main actor.
final nonisolated class SessionTextTranslator: TextTranslating {
    private let session: TranslationSession

    init(session: TranslationSession) {
        self.session = session
    }

    @concurrent func translate(_ texts: [String]) async throws -> [String?] {
        let requests = texts.enumerated().map { index, text in
            TranslationSession.Request(sourceText: text, clientIdentifier: String(index))
        }
        let responses = try await session.translations(from: requests)
        return Self.answers(count: texts.count, responses: responses.map { ($0.clientIdentifier, $0.targetText) })
    }

    /// One text at a time: a batch's answers come back without their attributes (measured on macOS 26.6).
    @available(macOS 26.4, *)
    @concurrent func translate(_ texts: [AttributedString]) async throws -> [AttributedString?] {
        var answers: [AttributedString?] = []
        for text in texts {
            try Task.checkCancellation()
            try await answers.append(session.translate(text).attributedTargetText)
        }
        return answers
    }

    /// Answers in the order of the requests, from `responses` matched by identifier; an unknown identifier is ignored.
    static func answers<Answer>(count: Int, responses: [(String?, Answer)]) -> [Answer?] {
        var answers = [Answer?](repeating: nil, count: count)
        for (identifier, answer) in responses {
            if let index = identifier.flatMap(Int.init), answers.indices.contains(index) {
                answers[index] = answer
            }
        }
        return answers
    }
}
