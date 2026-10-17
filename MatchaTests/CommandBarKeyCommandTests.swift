import Foundation
@testable import Matcha
import Testing

struct CommandBarKeyCommandTests {
    @Test(arguments: [
        ("moveUp:", CommandBarKeyCommand.moveUp),
        ("insertBacktab:", .moveUp),
        ("moveDown:", .moveDown),
        ("insertTab:", .moveDown),
        ("insertNewline:", .submit),
        ("insertNewlineIgnoringFieldEditor:", .submit),
        ("insertLineBreak:", .submit),
        ("cancelOperation:", .cancel),
        ("complete:", .cancel),
    ])
    func `selectors map to commands`(selector: String, command: CommandBarKeyCommand) {
        #expect(CommandBarKeyCommand(selectorName: selector) == command)
    }

    @Test(arguments: ["moveLeft:", "moveRight:", "deleteBackward:", "selectAll:", "insertText:", "moveUp", ""])
    func `other selectors are ignored`(selector: String) {
        #expect(CommandBarKeyCommand(selectorName: selector) == nil)
    }
}
