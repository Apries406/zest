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

    @Test func formatsReplies() {
        #expect(ShellProtocol.format(.pass, sequence: "3") == "r\(s)3\(s)pass\n")
        #expect(ShellProtocol.format(.set(cursor: 2, buffer: "a\nb"), sequence: "3") == "r\(s)3\(s)set\(s)2\(s)a\u{1e}b\n")
    }
}
