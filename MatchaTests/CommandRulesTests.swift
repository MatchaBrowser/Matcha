import AppKit
@testable import Matcha
import Testing

/// Rules of the menu commands taken out of their responders (review TS12): Edit > Find, and the key press that
/// records a shortcut in Settings > Shortcuts.
@MainActor
struct CommandRulesTests {
    private static func tag(_ action: NSFindPanelAction) -> Int {
        Int(action.rawValue)
    }

    @Test func `find and use selection are always on, next and previous once something was searched`() {
        for hasQuery in [false, true] {
            #expect(PageFindResponder.canPerform(tag: Self.tag(.showFindPanel), hasQuery: hasQuery))
            #expect(PageFindResponder.canPerform(tag: Self.tag(.setFindString), hasQuery: hasQuery))
            #expect(PageFindResponder.canPerform(tag: Self.tag(.next), hasQuery: hasQuery) == hasQuery)
            #expect(PageFindResponder.canPerform(tag: Self.tag(.previous), hasQuery: hasQuery) == hasQuery)
            // Find and Replace stays off, and so does an unknown tag.
            #expect(!PageFindResponder.canPerform(tag: Self.tag(.replace), hasQuery: hasQuery))
            #expect(!PageFindResponder.canPerform(tag: -1, hasQuery: hasQuery))
        }
        // Without a browser window in front, nothing.
        #expect(!PageFindResponder().canPerform(tag: Self.tag(.showFindPanel)))
    }

    private static func keyDown(_ characters: String, keyCode: UInt16, modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
        try #require(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode,
        ))
    }

    @Test func `escape cancels, delete clears, a key with modifiers is the shortcut`() throws {
        #expect(try ShortcutRecorder.press(Self.keyDown("\u{1B}", keyCode: 53)) == .cancel)
        #expect(try ShortcutRecorder.press(Self.keyDown("\u{7F}", keyCode: 51)) == .clear)
        #expect(try ShortcutRecorder.press(Self.keyDown(
            String(UnicodeScalar(UInt16(NSDeleteFunctionKey)).map(Character.init) ?? " "),
            keyCode: 117,
        )) == .clear)
        #expect(try ShortcutRecorder.press(Self.keyDown("k", keyCode: 40, modifiers: .command)) == .shortcut(ShortcutKey("k", .command)))
        // With a modifier, Escape and Delete are shortcuts like the others.
        #expect(try ShortcutRecorder.press(Self.keyDown("\u{1B}", keyCode: 53, modifiers: .command)) == .shortcut(ShortcutKey(
            .escape,
            .command,
        )))
        #expect(try ShortcutRecorder.press(Self.keyDown("\u{7F}", keyCode: 51, modifiers: .option)) == .shortcut(ShortcutKey(
            .delete,
            .option,
        )))
        // A key no shortcut can use.
        #expect(try ShortcutRecorder.press(Self.keyDown("é è", keyCode: 19)) == .unusable)
    }
}
