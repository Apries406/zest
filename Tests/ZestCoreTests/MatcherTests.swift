import Testing
@testable import ZestCore

@Suite struct MatcherTests {
    @Test func emptyQueryMatchesEverything() {
        #expect(Matcher.match("", "anything")?.score == 0)
    }

    @Test func prefixBeatsSubstringBeatsFuzzy() throws {
        let prefix = try #require(Matcher.match("che", "checkout"))
        let substring = try #require(Matcher.match("che", "recheck"))
        let fuzzy = try #require(Matcher.match("cko", "checkout"))
        #expect(prefix.score > substring.score)
        #expect(substring.score > fuzzy.score)
    }

    @Test func caseInsensitive() {
        #expect(Matcher.match("DESK", "Desktop") != nil)
    }

    @Test func prefixOnlyRejectsFuzzy() {
        #expect(Matcher.match("cko", "checkout", fuzzy: false) == nil)
        #expect(Matcher.match("che", "checkout", fuzzy: false) != nil)
    }

    @Test func noMatch() {
        #expect(Matcher.match("xyz", "checkout") == nil)
        #expect(Matcher.match("longer than candidate", "short") == nil)
    }

    @Test func highlightIndices() {
        #expect(Matcher.match("co", "commit")?.indices == [0, 1])
        #expect(Matcher.match("mit", "commit")?.indices == [3, 4, 5])
        #expect(Matcher.match("cmt", "commit")?.indices == [0, 2, 5])
    }

    @Test func wordBoundariesWin() throws {
        let boundary = try #require(Matcher.match("pr", "git-pr"))
        let inside = try #require(Matcher.match("pr", "upright"))
        #expect(boundary.score > inside.score)
    }
}
