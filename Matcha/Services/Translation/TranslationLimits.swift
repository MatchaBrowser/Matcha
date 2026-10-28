import Foundation

/// Bounds of a page's translation (task 9.1): a piece too long stays as it is (never cut), and the texts go to the
/// translator in batches of bounded size, so that a huge page neither blocks the translator nor fills the memory.
/// Pure type.
nonisolated enum TranslationLimits {
    /// Longest piece translated, in characters; a longer one stays in its language.
    static let maximumPieceLength = 5000
    /// Longest block translated whole by the rich-text method; a longer one goes through the plain-text method.
    static let maximumRichBlockLength = 10000
    /// Characters of a batch.
    static let maximumBatchLength = 20000
    /// Texts of a batch.
    static let maximumBatchCount = 100
    /// Blocks read from the page at a time (task 9.2): the page is translated in steps, those on screen first; a short
    /// step shows the first translations sooner.
    static let maximumBlocksPerCollect = 50
    /// Pieces of a block; a block with more (a huge list of links in one element) stays in its language.
    static let maximumPiecesPerBlock = 300

    /// `items` in order, in batches of at most `maximumBatchCount` items and `maximumBatchLength` characters (an item
    /// longer than that makes a batch of its own).
    static func batches<Item>(of items: [Item], length: (Item) -> Int) -> [[Item]] {
        var batches: [[Item]] = []
        var batch: [Item] = []
        var batchLength = 0
        for item in items {
            let itemLength = length(item)
            if !batch.isEmpty, batch.count == maximumBatchCount || batchLength + itemLength > maximumBatchLength {
                batches.append(batch)
                batch = []
                batchLength = 0
            }
            batch.append(item)
            batchLength += itemLength
        }
        if !batch.isEmpty {
            batches.append(batch)
        }
        return batches
    }
}
