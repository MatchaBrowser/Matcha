import Foundation
@testable import Matcha
import Testing

struct CommandMatcherTests {
    private func match(
        _ text: String,
        titles: [String],
        url: String? = nil,
        minimumTier: MatchTier = .fuzzy,
    ) -> CommandMatch? {
        CommandMatcher.match(query(text), titles: titles, url: url.flatMap(URL.init(string:)), minimumTier: minimumTier)
    }

    @Test func `exact title or address`() {
        #expect(match("github", titles: ["GitHub"])?.tier == .exact)
        #expect(match("  GITHUB ", titles: ["Some Page", "GitHub"])?.tier == .exact)
        #expect(match("github.com", titles: ["Accueil"], url: "https://www.github.com/")?.tier == .exact)
        #expect(match("https://github.com", titles: ["Accueil"], url: "http://github.com")?.tier == .exact)
        #expect(match("github", titles: ["GitHub"])?.quality == 100)
    }

    @Test func `a pasted address of the same page is exact`() {
        #expect(match("https://www.apple.com/", titles: ["Apple"], url: "https://www.apple.com/")?.tier == .exact)
        #expect(match("apple.com/", titles: ["Apple"], url: "https://www.apple.com/")?.tier == .exact)
        #expect(match("http://apple.com/#footer", titles: ["Apple"], url: "https://www.apple.com/")?.tier == .exact)
        #expect(match("https://example.com/a%20b", titles: ["Doc"], url: "https://example.com/a%20b")?.tier == .exact)
        #expect(match("https://example.com/docs/", titles: ["Doc"], url: "https://example.com/docs")?.tier == .exact)
        #expect(match("https://www.apple.com/", titles: ["Apple"], url: "https://www.apple.com/fr/")?.tier == .prefix)
    }

    @Test func `prefix of the title or of the address without scheme and www`() {
        #expect(match("git", titles: ["GitHub"])?.tier == .prefix)
        #expect(match("github.com/app", titles: ["Apple"], url: "https://www.github.com/apple")?.tier == .prefix)
        #expect(match("https://git", titles: ["Apple"], url: "https://www.github.com/apple")?.tier == .prefix)
        #expect(match("www.git", titles: ["Apple"], url: "https://github.com/apple")?.tier == .prefix)
    }

    @Test func `word prefixes in any order across title and address`() {
        let found = match("swift apple", titles: ["Swift Forums"], url: "https://forums.apple.com")
        #expect(found?.tier == .wordPrefix)
        #expect(match("for swi", titles: ["Swift Forums"])?.tier == .wordPrefix)
        #expect(match("swift banana", titles: ["Swift Forums"], url: "https://forums.apple.com") == nil)
        // A typed word split by punctuation counts as its pieces.
        #expect(match("node.js docs", titles: ["Docs | Node.js"], url: "https://nodejs.org/en/docs")?.tier == .wordPrefix)
        #expect(match("6.4 swift", titles: ["What's new in Swift 6.4"])?.tier == .wordPrefix)
        #expect(match("react-native docs", titles: ["Docs", "React Native"])?.tier == .wordPrefix)
        // When it is a single piece, it stays whole: “c++” is not reduced to “c”.
        #expect(match("c++ docs", titles: ["Docs", "Calendar"]) == nil)
    }

    @Test func `substring needs two characters`() {
        #expect(match("ub", titles: ["GitHub"])?.tier == .substring)
        #expect(match("hub.co", titles: ["Accueil"], url: "https://github.com")?.tier == .substring)
        #expect(match("u", titles: ["GitHub"]) == nil)
    }

    @Test func `fuzzy needs three characters and a word start`() {
        let found = match("gthb", titles: ["GitHub"])
        #expect(found?.tier == .fuzzy)
        #expect(found?.quality == 66)
        #expect(match("gh", titles: ["GitHub"]) == nil)
        #expect(match("thb", titles: ["GitHub"]) == nil)
        #expect(CommandMatcher.fuzzyQuality(of: "gthb", in: "github") == 66)
        #expect(CommandMatcher.fuzzyQuality(of: "ghb", in: "github") == 50)
        #expect(CommandMatcher.fuzzyQuality(of: "thb", in: "github") == nil)
    }

    @Test func `fuzzy keeps the most compact window`() {
        #expect(CommandMatcher.fuzzyQuality(of: "nfx", in: "nofix netflix") == 60)
        #expect(match("nfx", titles: ["nofix netflix"])?.quality == 60)
    }

    @Test func `scattered letters are rejected`() {
        #expect(CommandMatcher.fuzzyQuality(of: "gdrv", in: "google drive") == 36)
        #expect(match("gdrv", titles: ["Google Drive"])?.quality == 36)
        #expect(CommandMatcher.fuzzyQuality(of: "gdrv", in: "great dark river valley") == 28)
        #expect(match("gdrv", titles: ["Great Dark River Valley"]) == nil)
    }

    @Test func `fuzzy ignores queries longer than the limit`() {
        let long = String(repeating: "a", count: CommandMatcher.maximumFuzzyLength + 1)
        #expect(match("\(long)z", titles: [long + "bz"]) == nil)
    }

    @Test func `actions need at least a word prefix`() {
        let titles = ["Settings", "settings", "preferences", "options"]
        #expect(match("sett", titles: titles, minimumTier: .wordPrefix)?.tier == .prefix)
        #expect(match("ttings", titles: titles, minimumTier: .wordPrefix) == nil)
        #expect(match("stg", titles: titles, minimumTier: .wordPrefix) == nil)
        #expect(match("ttings", titles: titles)?.tier == .substring)
    }

    @Test func `fuzzy buckets`() {
        #expect(CommandMatch(tier: .fuzzy, quality: 80).fuzzyBucket == 3)
        #expect(CommandMatch(tier: .fuzzy, quality: 75).fuzzyBucket == 3)
        #expect(CommandMatch(tier: .fuzzy, quality: 60).fuzzyBucket == 2)
        #expect(CommandMatch(tier: .fuzzy, quality: 36).fuzzyBucket == 1)
        #expect(CommandMatch(tier: .prefix, quality: 100).fuzzyBucket == 0)
        #expect(match("gthb", titles: ["GitHub"])?.fuzzyBucket == 2)
        #expect(MatchTier.exact > .prefix && MatchTier.substring > .fuzzy)
    }
}
