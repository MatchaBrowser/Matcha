import Foundation

nonisolated extension SymbolChoice {
    /// Icônes proposées pour un Space, pleines pour rester lisibles en petit dans la barre. En premier, les symboles
    /// donnés tour à tour aux nouveaux Spaces (`BrowserSession.spaceSymbols`), dans le même ordre.
    static let spaceIcons = [
        SymbolChoice(name: "circle.fill", title: LocalizedStringResource("Circle", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "star.fill", title: LocalizedStringResource("Star", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "heart.fill", title: LocalizedStringResource("Heart", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "bolt.fill", title: LocalizedStringResource("Lightning Bolt", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "leaf.fill", title: LocalizedStringResource("Leaf", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "moon.fill", title: LocalizedStringResource("Moon", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "flame.fill", title: LocalizedStringResource("Flame", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "briefcase.fill", title: LocalizedStringResource("Briefcase", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "house.fill", title: LocalizedStringResource("House", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "person.fill", title: LocalizedStringResource("Person", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "person.2.fill", title: LocalizedStringResource("People", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(
            name: "building.2.fill",
            title: LocalizedStringResource("Buildings", comment: "Icon choice (SF Symbol): two office buildings"),
        ),
        SymbolChoice(name: "graduationcap.fill", title: LocalizedStringResource("Graduation Cap", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "book.fill", title: LocalizedStringResource("Book", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "lightbulb.fill", title: LocalizedStringResource("Light Bulb", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "paintbrush.fill", title: LocalizedStringResource("Paintbrush", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "hammer.fill", title: LocalizedStringResource("Hammer", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(
            name: "wrench.and.screwdriver.fill",
            title: LocalizedStringResource("Tools", comment: "Icon choice (SF Symbol): a wrench and a screwdriver"),
        ),
        SymbolChoice(name: "laptopcomputer", title: LocalizedStringResource("Laptop", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "terminal.fill", title: LocalizedStringResource("Terminal", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "chart.bar.fill", title: LocalizedStringResource("Chart", comment: "Icon choice (SF Symbol): a bar chart")),
        SymbolChoice(name: "doc.text.fill", title: LocalizedStringResource("Document", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(
            name: "bubble.left.and.bubble.right.fill",
            title: LocalizedStringResource("Conversation", comment: "Icon choice (SF Symbol): two speech bubbles"),
        ),
        SymbolChoice(name: "cart.fill", title: LocalizedStringResource("Shopping Cart", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "bag.fill", title: LocalizedStringResource("Shopping Bag", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "creditcard.fill", title: LocalizedStringResource("Credit Card", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "gift.fill", title: LocalizedStringResource("Gift", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "gamecontroller.fill", title: LocalizedStringResource("Game Controller", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "music.note", title: LocalizedStringResource("Music", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "film.fill", title: LocalizedStringResource("Film", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "camera.fill", title: LocalizedStringResource(
            "Camera Icon",
            defaultValue: "Camera",
            comment: "Icon choice (SF Symbol): a photo camera. Distinct from the Camera website permission.",
        )),
        SymbolChoice(name: "puzzlepiece.fill", title: LocalizedStringResource("Puzzle Piece", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "dumbbell.fill", title: LocalizedStringResource("Dumbbell", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "fork.knife", title: LocalizedStringResource("Fork and Knife", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(
            name: "cup.and.saucer.fill",
            title: LocalizedStringResource("Coffee Cup", comment: "Icon choice (SF Symbol): a cup on a saucer"),
        ),
        SymbolChoice(name: "pawprint.fill", title: LocalizedStringResource("Paw Print", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "airplane", title: LocalizedStringResource("Airplane", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "car.fill", title: LocalizedStringResource("Car", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "globe", title: LocalizedStringResource("Globe", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "mountain.2.fill", title: LocalizedStringResource("Mountains", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "tree.fill", title: LocalizedStringResource("Tree", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "sun.max.fill", title: LocalizedStringResource("Sun", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "cloud.fill", title: LocalizedStringResource("Cloud", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "sparkles", title: LocalizedStringResource("Sparkles", comment: "Icon choice (SF Symbol)")),
        SymbolChoice(name: "flag.fill", title: LocalizedStringResource("Flag", comment: "Icon choice (SF Symbol)")),
    ]
}
