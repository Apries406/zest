import Testing
@testable import ZestCore

@Suite struct ShellProtocolTests {
    let s = "\u{1f}"

    @Test func parsesLine() {
        let message = ShellProtocol.parse(Substring("line\(s)42-7\(s)/tmp\(s)3\(s)git\u{1e}ls"))
        #expect(message == .line(.init(session: "42-7", cwd: "/tmp", cursor: 3, buffer: "git\nls")))
    }

    @Test func parsesKey() {
        let message = ShellProtocol.parse(Substring("key\(s)5\(s)tab\(s)1-2\(s)/\(s)4\(s)git "))
        #expect(message == .key(sequence: "5", key: .tab, .init(session: "1-2", cwd: "/", cursor: 4, buffer: "git ")))
    }

    @Test func parsesHelloAndAliases() {
        #expect(ShellProtocol.parse(Substring("hello\(s)a\(s)99\(s)com.apple.Terminal\(s)/h")) ==
            .hello(session: "a", pid: 99, app: "com.apple.Terminal", historyFile: "/h"))
        #expect(ShellProtocol.parse(Substring("aliases\(s)a\(s)g=git\(s)ll=ls -l=x")) ==
            .aliases(session: "a", ["g": "git", "ll": "ls -l=x"]))
    }

    @Test func rejectsGarbage() {
        #expect(ShellProtocol.parse("") == nil)
        #expect(ShellProtocol.parse("key\(s)1\(s)nope\(s)a\(s)/\(s)0\(s)") == nil)
        #expect(ShellProtocol.parse("line\(s)a\(s)/\(s)notanumber\(s)x") == nil)
    }

    @Test func parsesPosition() {
        #expect(ShellProtocol.parse(Substring("pos\(s)a\(s)12\(s)17\(s)35\(s)99\(s)4")) ==
            .position(session: "a", .init(row: 12, column: 17, rows: 35, columns: 99, cursor: 4)))
        // Without the cursor field, the position is where the line starts.
        #expect(ShellProtocol.parse(Substring("pos\(s)a\(s)1\(s)1\(s)24\(s)80")) ==
            .position(session: "a", .init(row: 1, column: 1, rows: 24, columns: 80, cursor: 0)))
        #expect(ShellProtocol.parse(Substring("pos\(s)a\(s)0\(s)1\(s)24\(s)80")) == nil)
        #expect(ShellProtocol.parse(Substring("pos\(s)a\(s)1\(s)1\(s)24")) == nil)
    }

    @Test func gridCellFollowsTheCursorAndWraps() {
        // The terminal reported row 3, column 17 while the cursor was at index 2.
        let position = ShellProtocol.GridPosition(row: 3, column: 17, rows: 24, columns: 20, cursor: 2)
        #expect(position.cell(at: 2) == (2, 16))
        #expect(position.cell(at: 0) == (2, 14))
        #expect(position.cell(at: 5) == (2, 19))  // the last column
        #expect(position.cell(at: 6) == (3, 0))   // wrapped to the next row
        #expect(position.cell(at: 27) == (4, 1))
    }

    @Test func formatsReplies() {
        #expect(ShellProtocol.format(.pass, sequence: "3") == "r\(s)3\(s)pass\n")
        #expect(ShellProtocol.format(.set(cursor: 2, buffer: "a\nb"), sequence: "3") == "r\(s)3\(s)set\(s)2\(s)a\u{1e}b\n")
    }
}
