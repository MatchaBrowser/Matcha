import Foundation
@testable import Matcha
import Testing

/// Banner for a page's permission requests (task 5.2): one request at a time, answers, remembered decisions, denial
/// when the page changes or closes; and the answer to WebKit, given only once.
@MainActor
struct PermissionPromptQueueTests {
    private let queue = PermissionPromptQueue()
    private let recorder = PermissionRecorder()
    private let scope = SitePermissionScope(store: SitePermissionStore(context: nil), profileID: UUID())

    @Test func `requests are shown one at a time, in order`() {
        let first = SitePermissionRequest.test([.camera], scope: scope, response: recorder.response())
        let second = SitePermissionRequest.test([.microphone], origin: TestOrigins.other, scope: scope, response: recorder.response())
        queue.enqueue(first)
        queue.enqueue(second)
        #expect(queue.current?.id == first.id)
        // Without an answer, nothing is sent: the page waits.
        #expect(recorder.answers.isEmpty)

        queue.answer(.allowOnce)
        #expect(recorder.answers == [true])
        #expect(queue.current?.id == second.id)
        queue.answer(.allowOnce)
        #expect(recorder.answers == [true, true])
        #expect(queue.current == nil)
    }

    @Test func `allow once remembers nothing`() {
        queue.enqueue(.test([.camera, .microphone], scope: scope, response: recorder.response()))
        queue.answer(.allowOnce)
        #expect(recorder.answers == [true])
        #expect(scope.decisions(for: TestOrigins.meet).isEmpty)
    }

    @Test func `always allow and don't allow are remembered for what was asked`() {
        queue.enqueue(.test([.camera, .microphone], asked: [.camera], scope: scope, response: recorder.response()))
        queue.enqueue(.test([.microphone], origin: TestOrigins.other, scope: scope, response: recorder.response()))

        queue.answer(.alwaysAllow)
        #expect(scope.decisions(for: TestOrigins.meet) == [.camera: .allow])
        queue.answer(.deny)
        #expect(scope.decisions(for: TestOrigins.other) == [.microphone: .deny])
        #expect(recorder.answers == [true, false])
    }

    @Test func `a page without a website is never remembered`() {
        let request = SitePermissionRequest.test([.camera], origin: nil, scope: scope, response: recorder.response())
        #expect(!request.canRemember)
        #expect(!SitePermissionRequest.test([.camera], scope: nil, response: recorder.response()).canRemember)
        queue.enqueue(request)
        queue.answer(.deny)
        #expect(recorder.answers == [false])
        #expect(scope.store.entries.isEmpty)
    }

    @Test func `a saved answer also settles the next requests it covers`() {
        let later = PermissionRecorder()
        queue.enqueue(.test([.camera], scope: scope, response: recorder.response()))
        queue.enqueue(.test([.camera], scope: scope, response: later.response()))
        queue.enqueue(.test([.camera], origin: TestOrigins.other, scope: scope, response: later.response()))

        queue.answer(.alwaysAllow)
        #expect(recorder.answers == [true])
        #expect(later.answers == [true])
        // The other site is still waiting for its answer.
        #expect(queue.requests.map(\.origin) == [TestOrigins.other])
    }

    @Test func `leaving the page denies everything that waits`() {
        queue.enqueue(.test([.camera], scope: scope, response: recorder.response()))
        queue.enqueue(.test([.microphone], scope: scope, response: recorder.response()))
        queue.denyAll()
        #expect(recorder.answers == [false, false])
        #expect(queue.current == nil)
        // Nothing is remembered: the page can ask again.
        #expect(scope.store.entries.isEmpty)
        queue.answer(.alwaysAllow)
        #expect(recorder.answers == [false, false])
    }

    @Test func `a response is sent once`() {
        let response = recorder.response()
        response.send(true)
        response.send(false)
        #expect(recorder.answers == [true])
        #expect(response.hasAnswered)
    }

    /// WebKit raises an exception if its handler is released without being called: the answer denies by itself.
    @Test func `a response released without an answer denies`() async throws {
        do {
            let response = recorder.response()
            #expect(!response.hasAnswered)
        }
        try await waitUntil { recorder.answers == [false] }
    }
}
