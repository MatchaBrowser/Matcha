import Foundation

/// Texts of the notes editor in the app's language (task 12.2), keyed as its page reads them: `slash.<item>.title` and
/// `slash.<item>.description` for the items of the “/” menu, `slash.group.<OpenBlock's group>` for its sections,
/// `bubble.<item>` for the formatting buttons, `placeholder` for an empty note. OpenBlock lets the app replace only
/// these: its other texts (block types of the formatting bar, colors, links, tables) stay in English.
nonisolated enum NoteEditorTexts {
    static var current: [String: String] {
        var texts = slashItems.merging(bubbleItems) { first, _ in first }
        texts["placeholder"] = String(
            localized: "Note Placeholder",
            defaultValue: "Type “/” for commands",
            comment: "Notes editor: text shown in an empty note",
        )
        return texts
    }

    private static var slashItems: [String: String] {
        [
            "slash.group.Basic blocks": String(
                localized: "Note Group Basic",
                defaultValue: "Basic Blocks",
                comment: "Notes editor, “/” menu: section",
            ),
            "slash.group.Lists": String(localized: "Note Group Lists", defaultValue: "Lists", comment: "Notes editor, “/” menu: section"),
            "slash.group.Layout": String(
                localized: "Note Group Layout",
                defaultValue: "Layout",
                comment: "Notes editor, “/” menu: section",
            ),
            "slash.heading1.title": String(
                localized: "Note Heading 1",
                defaultValue: "Heading 1",
                comment: "Notes editor, “/” menu: block",
            ),
            "slash.heading1.description": String(
                localized: "Note Heading 1 Description",
                defaultValue: "Large section heading",
                comment: "Notes editor, “/” menu: description of Heading 1",
            ),
            "slash.heading2.title": String(
                localized: "Note Heading 2",
                defaultValue: "Heading 2",
                comment: "Notes editor, “/” menu: block",
            ),
            "slash.heading2.description": String(
                localized: "Note Heading 2 Description",
                defaultValue: "Medium section heading",
                comment: "Notes editor, “/” menu: description of Heading 2",
            ),
            "slash.heading3.title": String(
                localized: "Note Heading 3",
                defaultValue: "Heading 3",
                comment: "Notes editor, “/” menu: block",
            ),
            "slash.heading3.description": String(
                localized: "Note Heading 3 Description",
                defaultValue: "Small section heading",
                comment: "Notes editor, “/” menu: description of Heading 3",
            ),
            "slash.bulletList.title": String(
                localized: "Note Bulleted List",
                defaultValue: "Bulleted List",
                comment: "Notes editor, “/” menu: block",
            ),
            "slash.bulletList.description": String(
                localized: "Note Bulleted List Description",
                defaultValue: "Create a bulleted list",
                comment: "Notes editor, “/” menu: description of Bulleted List",
            ),
            "slash.orderedList.title": String(
                localized: "Note Numbered List",
                defaultValue: "Numbered List",
                comment: "Notes editor, “/” menu: block",
            ),
            "slash.orderedList.description": String(
                localized: "Note Numbered List Description",
                defaultValue: "Create a numbered list",
                comment: "Notes editor, “/” menu: description of Numbered List",
            ),
            "slash.checklist.title": String(
                localized: "Note To-Do List",
                defaultValue: "To-Do List",
                comment: "Notes editor, “/” menu: block",
            ),
            "slash.checklist.description": String(
                localized: "Note To-Do List Description",
                defaultValue: "Track tasks with checkboxes",
                comment: "Notes editor, “/” menu: description of To-Do List",
            ),
            "slash.quote.title": String(localized: "Note Quote", defaultValue: "Quote", comment: "Notes editor, “/” menu: block"),
            "slash.quote.description": String(
                localized: "Note Quote Description",
                defaultValue: "Capture a quotation",
                comment: "Notes editor, “/” menu: description of Quote",
            ),
            "slash.calloutInfo.title": String(localized: "Note Callout", defaultValue: "Callout", comment: "Notes editor, “/” menu: block"),
            "slash.calloutInfo.description": String(
                localized: "Note Callout Description",
                defaultValue: "Highlight important information",
                comment: "Notes editor, “/” menu: description of Callout",
            ),
            "slash.calloutWarning.title": String(
                localized: "Note Warning",
                defaultValue: "Warning",
                comment: "Notes editor, “/” menu: block (a callout)",
            ),
            "slash.calloutWarning.description": String(
                localized: "Note Warning Description",
                defaultValue: "Show a warning message",
                comment: "Notes editor, “/” menu: description of Warning",
            ),
            "slash.calloutSuccess.title": String(
                localized: "Note Success",
                defaultValue: "Success",
                comment: "Notes editor, “/” menu: block (a callout)",
            ),
            "slash.calloutSuccess.description": String(
                localized: "Note Success Description",
                defaultValue: "Show a success message",
                comment: "Notes editor, “/” menu: description of Success",
            ),
            "slash.calloutError.title": String(
                localized: "Note Error",
                defaultValue: "Error",
                comment: "Notes editor, “/” menu: block (a callout)",
            ),
            "slash.calloutError.description": String(
                localized: "Note Error Description",
                defaultValue: "Show an error message",
                comment: "Notes editor, “/” menu: description of Error",
            ),
            "slash.codeBlock.title": String(
                localized: "Note Code Block",
                defaultValue: "Code Block",
                comment: "Notes editor, “/” menu: block",
            ),
            "slash.codeBlock.description": String(
                localized: "Note Code Block Description",
                defaultValue: "Show a block of code",
                comment: "Notes editor, “/” menu: description of Code Block",
            ),
            "slash.divider.title": String(localized: "Note Divider", defaultValue: "Divider", comment: "Notes editor, “/” menu: block"),
            "slash.divider.description": String(
                localized: "Note Divider Description",
                defaultValue: "Separate two sections",
                comment: "Notes editor, “/” menu: description of Divider",
            ),
            "slash.columns2.title": String(
                localized: "Note Two Columns",
                defaultValue: "2 Columns",
                comment: "Notes editor, “/” menu: block",
            ),
            "slash.columns2.description": String(
                localized: "Note Two Columns Description",
                defaultValue: "Split into two columns",
                comment: "Notes editor, “/” menu: description of 2 Columns",
            ),
            "slash.columns3.title": String(
                localized: "Note Three Columns",
                defaultValue: "3 Columns",
                comment: "Notes editor, “/” menu: block",
            ),
            "slash.columns3.description": String(
                localized: "Note Three Columns Description",
                defaultValue: "Split into three columns",
                comment: "Notes editor, “/” menu: description of 3 Columns",
            ),
            "slash.columnsSidebar.title": String(
                localized: "Note Side Column",
                defaultValue: "Side Column",
                comment: "Notes editor, “/” menu: block (a narrow column on the left and a wide one)",
            ),
            "slash.columnsSidebar.description": String(
                localized: "Note Side Column Description",
                defaultValue: "A narrow column next to the main one",
                comment: "Notes editor, “/” menu: description of Side Column",
            ),
            "slash.table.title": String(localized: "Note Table", defaultValue: "Table", comment: "Notes editor, “/” menu: block"),
            "slash.table.description": String(
                localized: "Note Table Description",
                defaultValue: "Insert a 3 × 3 table",
                comment: "Notes editor, “/” menu: description of Table",
            ),
            "slash.table2x2.title": String(
                localized: "Note Small Table",
                defaultValue: "Table 2 × 2",
                comment: "Notes editor, “/” menu: block",
            ),
            "slash.table2x2.description": String(
                localized: "Note Small Table Description",
                defaultValue: "Insert a small 2 × 2 table",
                comment: "Notes editor, “/” menu: description of Table 2 × 2",
            ),
            "slash.table4x4.title": String(
                localized: "Note Large Table",
                defaultValue: "Table 4 × 4",
                comment: "Notes editor, “/” menu: block",
            ),
            "slash.table4x4.description": String(
                localized: "Note Large Table Description",
                defaultValue: "Insert a large 4 × 4 table",
                comment: "Notes editor, “/” menu: description of Table 4 × 4",
            ),
        ]
    }

    private static var bubbleItems: [String: String] {
        [
            "bubble.bold": String(
                localized: "Note Bold",
                defaultValue: "Bold (⌘B)",
                comment: "Notes editor: tooltip of a formatting button",
            ),
            "bubble.italic": String(
                localized: "Note Italic",
                defaultValue: "Italic (⌘I)",
                comment: "Notes editor: tooltip of a formatting button",
            ),
            "bubble.underline": String(
                localized: "Note Underline",
                defaultValue: "Underline (⌘U)",
                comment: "Notes editor: tooltip of a formatting button",
            ),
            "bubble.strikethrough": String(
                localized: "Note Strikethrough",
                defaultValue: "Strikethrough",
                comment: "Notes editor: tooltip of a formatting button",
            ),
            "bubble.code": String(
                localized: "Note Inline Code",
                defaultValue: "Inline Code",
                comment: "Notes editor: tooltip of a formatting button (code within a line of text)",
            ),
            "bubble.alignLeft": String(
                localized: "Note Align Left",
                defaultValue: "Align Left",
                comment: "Notes editor: tooltip of a formatting button",
            ),
            "bubble.alignCenter": String(
                localized: "Note Center",
                defaultValue: "Center",
                comment: "Notes editor: tooltip of a formatting button",
            ),
            "bubble.alignRight": String(
                localized: "Note Align Right",
                defaultValue: "Align Right",
                comment: "Notes editor: tooltip of a formatting button",
            ),
        ]
    }
}
