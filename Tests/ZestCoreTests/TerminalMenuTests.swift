import Testing
@testable import ZestCore

@Suite struct TerminalMenuTests {
    let controller = CompletionController(engine: Fixtures.engine())
    let s = "\u{1f}"

    @Test func terminalModeIsScopedToTheSession() {
        controller.handle(.terminal(session: "s"))
        controller.handle(.line(.init(session: "s", cwd: "/", cursor: 6, buffer: "git ch")))
        #expect(controller.current.terminalMenu)
        #expect(controller.current.visible)
        controller.handle(.line(.init(session: "other", cwd: "/", cursor: 6, buffer: "git ch")))
        #expect(!controller.current.terminalMenu)
    }

    @Test func formatsMenuWithTheOriginalLine() {
        controller.handle(.terminal(session: "s"))
        controller.handle(.line(.init(session: "s", cwd: "/", cursor: 6, buffer: "git ch")))
        let fields = TerminalMenu.format(controller.current).dropLast().split(separator: "\u{1f}", omittingEmptySubsequences: false)
        #expect(fields.prefix(4) == ["menu", "s", "6", "0"])
        #expect(fields.last == "git ch")
        #expect(fields[5].hasPrefix("checkout"))
        #expect(Int(fields[4]) == fields.count - 6)
    }

    @Test func hiddenMenuClearsTheTerminalList() {
        var state = CompletionController.State.hidden
        state.session = "s"
        #expect(TerminalMenu.format(state) == "menu\(s)s\(s)0\(s)0\(s)0\(s)\n")
    }

    @Test func selectionRemainsVisibleBeyondTheFirstPage() {
        controller.handle(.line(.init(session: "s", cwd: "/", cursor: 6, buffer: "git ch")))
        var state = controller.current
        let item = state.items[0]
        state.items = (0..<8).map { index in
            var next = item
            next.name = "item-\(index)"
            return next
        }
        state.selected = 6
        let fields = TerminalMenu.format(state).dropLast().split(separator: "\u{1f}", omittingEmptySubsequences: false)
        #expect(fields[3] == "3")
        #expect(fields[4] == "5")
        #expect(fields[5].hasPrefix("item-3"))
        #expect(fields[8].hasPrefix("item-6"))
    }

    @Test func candidateControlCharactersCannotInjectTerminalCommands() {
        controller.handle(.line(.init(session: "s", cwd: "/", cursor: 6, buffer: "git ch")))
        var state = controller.current
        state.items[0].name = "name\u{1b}[31m\n\u{1f}row"
        state.items[0].description = "\t说明\u{2028}第二行"
        let text = TerminalMenu.format(state)
        #expect(!text.contains("\u{1b}"))
        #expect(text.filter { $0 == "\n" }.count == 1)
        #expect(text.contains("name [31m  row   说明 第二行"))
    }

    @Test func terminalHandshake() {
        #expect(ShellProtocol.parse(Substring("terminal\(s)s")) == .terminal(session: "s"))
        #expect(ShellProtocol.parse(Substring("terminal\(s)s\(s)extra")) == nil)
    }
}
