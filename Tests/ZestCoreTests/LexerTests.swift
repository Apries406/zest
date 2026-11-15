import Testing
@testable import ZestCore

@Suite struct LexerTests {
    @Test func splitsWords() {
        let ctx = Lexer.context(buffer: "git commit -m", cursor: 13)
        #expect(ctx.words.map(\.value) == ["git", "commit"])
        #expect(ctx.current.value == "-m")
        #expect(ctx.current.start == 11)
    }

    @Test func emptyCurrentWordAfterSpace() {
        let ctx = Lexer.context(buffer: "git ", cursor: 4)
        #expect(ctx.words.map(\.value) == ["git"])
        #expect(ctx.current.value == "")
        #expect(ctx.current.start == 4)
    }

    @Test func unfinishedQuote() {
        let buffer = "git commit -m 'hello wor"
        let ctx = Lexer.context(buffer: buffer, cursor: buffer.count)
        #expect(ctx.current.value == "hello wor")
        #expect(ctx.current.openQuote == "'")
    }

    @Test func escapedSpace() {
        let buffer = #"cd My\ Dir/sub"#
        let ctx = Lexer.context(buffer: buffer, cursor: buffer.count)
        #expect(ctx.current.value == "My Dir/sub")
    }

    @Test func pipeStartsANewCommand() {
        let ctx = Lexer.context(buffer: "ls -la | grep fo", cursor: 16)
        #expect(ctx.words.map(\.value) == ["grep"])
        #expect(ctx.commandStart == 8)
    }

    @Test(arguments: ["a && b ", "a; b ", "a || b ", "(b ", "echo $(b "])
    func separators(buffer: String) {
        let ctx = Lexer.context(buffer: buffer, cursor: buffer.count)
        #expect(ctx.words.map(\.value) == ["b"])
    }

    @Test func redirectTarget() {
        let ctx = Lexer.context(buffer: "echo hi > ou", cursor: 12)
        #expect(ctx.currentIsRedirectTarget)
        #expect(ctx.words.map(\.value) == ["echo", "hi"])
    }

    @Test func numberedRedirect() {
        let ctx = Lexer.context(buffer: "make 2> log ", cursor: 12)
        #expect(ctx.words.map(\.value) == ["make"])
        #expect(!ctx.currentIsRedirectTarget)
    }

    @Test func cursorInsideWordReplacesWholeWord() {
        let ctx = Lexer.context(buffer: "git checkout", cursor: 7)
        #expect(ctx.current.value == "che")
        #expect(ctx.current.start == 4)
        #expect(ctx.current.end == 12)
    }

    @Test func unicodeOffsetsCountScalars() {
        let ctx = Lexer.context(buffer: "echo 🙂 fo", cursor: 9)
        #expect(ctx.current.value == "fo")
        #expect(ctx.current.start == 7)
    }

    @Test func shellEscaping() {
        #expect("My Doc.txt".shellEscaped() == #"My\ Doc.txt"#)
        #expect("it's".shellEscaped(inQuote: "\"") == "it's")
        #expect("a\"b".shellEscaped(inQuote: "\"") == #"a\"b"#)
    }
}
