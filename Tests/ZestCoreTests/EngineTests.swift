import Testing
@testable import ZestCore

@Suite struct EngineTests {
    let engine = Fixtures.engine()

    // MARK: Commands and subcommands

    @Test func commandsAtStart() {
        #expect(engine.names("gi") == ["git"])
        #expect(engine.names("").contains("sudo"))
    }

    @Test func subcommandsInSpecOrder() {
        #expect(engine.names("git ") == ["checkout", "commit", "clone"])
    }

    @Test func hiddenSubcommandNeedsTwoLetters() {
        #expect(!engine.names("git s").contains("secret"))
        #expect(engine.names("git se").contains("secret"))
    }

    @Test func aliasMatchesButMainNameIsShown() {
        let names = engine.names("git co")
        #expect(names.first == "checkout")
        #expect(names.contains("commit"))
    }

    @Test func fuzzyMatch() {
        #expect(engine.names("git cmt") == ["commit"])
    }

    // MARK: Options

    @Test func optionsAfterDash() {
        // Persistent options from `git` are valid in `git commit` too.
        #expect(engine.names("git commit -") == ["-m, --message", "--amend", "--format", "-C"])
    }

    @Test func longOptionsOnly() {
        #expect(engine.names("git commit --a").first == "--amend")
        #expect(!engine.names("git commit --a").contains("-C"))
    }

    @Test func usedOptionIsNotSuggestedAgain() {
        #expect(engine.names("git commit --amend -") == ["-m, --message", "--format", "-C"])
    }

    @Test func optionArgumentIsNotASubcommand() {
        // `-m` takes a value, so nothing is suggested for it.
        #expect(engine.names("git commit -m ").isEmpty)
        #expect(engine.names("git commit -m fix --am") == ["--amend"])
    }

    @Test func separatorOptionInsertsEquals() throws {
        let item = try #require(engine.first("git commit --form"))
        #expect(item.insertText == "--format=")
        #expect(!item.appendSpace)
    }

    @Test func valueAfterSeparator() throws {
        #expect(engine.names("git commit --format=") == ["short", "full"])
        let item = try #require(engine.first("git commit --format=fu"))
        let applied = Engine.apply(item, buffer: "git commit --format=fu", cursor: 22)
        #expect(applied.buffer == "git commit --format=full ")
    }

    @Test func persistentOptionWorksInSubcommand() {
        #expect(engine.names("git checkout -C De").first == "Desktop/")
    }

    @Test func showsOptionsWhenNothingElse() {
        #expect(engine.names("git commit ") == ["-m, --message", "--amend", "--format", "-C"])
    }

    // MARK: Arguments and generators

    @Test func generatorSuggestions() {
        #expect(engine.names("git checkout ") == ["main", "feature/x"])
        #expect(engine.names("git checkout fe") == ["feature/x"])
    }

    @Test func folderTemplate() {
        #expect(engine.names("git -C ") == ["Desktop/", "Documents/"])
    }

    @Test func loadSpecFromAnotherFile() {
        #expect(engine.names("tool sub ") == ["deep"])
    }

    @Test func isCommandCompletesTheRestAsACommand() {
        #expect(engine.names("sudo git ch").first == "checkout")
        #expect(engine.names("sudo -u root git ch").first == "checkout")
        #expect(engine.names("sudo gi") == ["git"])
    }

    @Test func aliasesExpand() {
        #expect(engine.names("g ch", aliases: ["g": "git"]).first == "checkout")
        #expect(engine.names("g", aliases: ["g": "git"]).contains("g"))
    }

    @Test func afterPipeAndAssignment() {
        #expect(engine.names("ls | git com") == ["commit"])
        #expect(engine.names("FOO=1 git com") == ["commit"])
    }

    // MARK: Files

    @Test func filesInFolder() {
        #expect(engine.names("cat Desktop/") == ["client/", "graphio/", "todo.txt"])
    }

    @Test func hiddenFilesNeedADot() {
        #expect(!engine.names("cat ./").contains(".hidden"))
        #expect(engine.names("cat ./.") == [".hidden"])
    }

    @Test func folderIsInsertedWithoutSpace() throws {
        let buffer = "git -C Desk"
        let item = try #require(engine.first(buffer))
        let applied = Engine.apply(item, buffer: buffer, cursor: buffer.count)
        #expect(applied.buffer == "git -C Desktop/")
        #expect(applied.cursor == 15)
    }

    @Test func fileNamesAreEscaped() throws {
        let buffer = "cat ./My"
        let item = try #require(engine.first(buffer))
        let applied = Engine.apply(item, buffer: buffer, cursor: buffer.count)
        #expect(applied.buffer == #"cat ./My\ Doc.txt "#)
    }

    @Test func homeFolder() {
        #expect(engine.names("cat ~/") == ["Projects/"])
    }

    @Test func redirectCompletesFiles() {
        #expect(engine.names("git status > no") == ["notes.md"])
    }

    // MARK: Inserting

    @Test func applyAddsSpace() throws {
        let item = try #require(engine.first("git chec"))
        let applied = Engine.apply(item, buffer: "git chec", cursor: 8)
        #expect(applied.buffer == "git checkout ")
        #expect(applied.cursor == 13)
    }

    @Test func applyInsideWordReplacesWholeWord() throws {
        let buffer = "git chXX main"
        let request = CompletionRequest(buffer: buffer, cursor: 6, cwd: "/work")
        let item = try #require(engine.complete(request).items.first)
        #expect(item.name == "checkout")
        let applied = Engine.apply(item, buffer: buffer, cursor: 6)
        #expect(applied.buffer == "git checkout main")
        #expect(applied.cursor == 13)
    }

    @Test func applyCursorMarker() {
        var item = Completion(
            kind: .argument, name: "x", insertText: "\"{cursor}\"", description: nil, icon: nil,
            matchedIndices: [], score: 0, appendSpace: true, replaceStart: 4, replaceEnd: 4,
            deprecated: false, usageKey: "")
        var applied = Engine.apply(item, buffer: "cmd ", cursor: 4)
        #expect(applied.buffer == "cmd \"\"")
        #expect(applied.cursor == 5)
        item.insertText = "y"
        applied = Engine.apply(item, buffer: "cmd ", cursor: 4)
        #expect(applied.buffer == "cmd y ")
    }

    // MARK: History and usage

    @Test func historyComesLast() {
        let names = engine.names("git co", history: ["git commit -m fix", "git commit -m fix", "ls"])
        #expect(names.last == "git commit -m fix")
        #expect(names.filter { $0 == "git commit -m fix" }.count == 1)
    }

    @Test func frequentCommandsComeFirst() {
        #expect(engine.names("s").first == "sudo")
        let history = ["tool sub deep", "tool sub", "tool"]
        #expect(engine.names("t", history: history).first == "tool")
    }

    @Test func historySkipsCommandsThatDoNotExist() {
        let names = engine.names("св", history: ["св ю", "св юю/"])
        #expect(!names.contains("св ю"))
        #expect(engine.names("ec", history: ["echo hi"]).contains("echo hi"))
    }

    @Test func wrongKeyboardLayout() throws {
        #expect(Engine.switchLayout("св") == "cd")
        #expect(Engine.switchLayout("пше") == "git")
        #expect(Engine.switchLayout("ls") == nil)
        let item = try #require(engine.first("пш"))
        #expect(item.name == "git")
        #expect(Engine.apply(item, buffer: "пш", cursor: 2).buffer == "git ")
    }

    @Test func usageMovesItemsUp() {
        let usage = UsageStore(url: nil)
        let engine = Fixtures.engine(usage: usage)
        #expect(engine.names("git ").first == "checkout")
        for _ in 0..<5 { usage.record("git|clone") }
        #expect(engine.names("git ").first == "clone")
    }

    // MARK: JavaScript generators (Fig compatibility)

    @Test func javaScriptPostProcess() {
        let result = engine.complete(CompletionRequest(buffer: "jst post ", cwd: "/work"))
        #expect(result.items.map(\.name) == ["a", "b"])
        #expect(result.items.first?.description == "item a")
    }

    @Test func javaScriptAsyncCustomGenerator() {
        #expect(engine.names("jst custom ") == ["x", "y"])
    }

    @Test func specThatLoadsAnotherSpec() {
        #expect(engine.names("speedy ch").first == "checkout")
    }

    @Test func optionsWithoutDash() throws {
        #expect(engine.names("ddx ").contains("bs"))
        #expect(engine.names("ddx +").contains("+short"))
        #expect(!engine.names("ddx ").contains("--verbose"))
        let item = try #require(engine.first("ddx b"))
        #expect(Engine.apply(item, buffer: "ddx b", cursor: 5).buffer == "ddx bs=")
    }

    @Test func subcommandThatLooksLikeAnOption() {
        #expect(engine.names("dsc -q -") == ["-a"])
    }

    @Test func precommandWithItsOwnSpec() {
        #expect(engine.names("command -") == ["-v"])
        #expect(engine.names("noglob git ch").first == "checkout")
    }

    @Test func insertTextHasNoNewlines() throws {
        let item = try #require(engine.complete(CompletionRequest(buffer: "runner ", cwd: "/work")).items.first)
        #expect(item.insertText == "-")
    }

    @Test func unknownCommandOnlyCompletesPaths() {
        #expect(engine.names("foo ").isEmpty)
        #expect(engine.names("foo Desktop/").contains("todo.txt"))
    }
}

@Suite struct GeneratorOutputTests {
    @Test func namesWithDescriptions() {
        let items = GeneratorRunner.split("build\tBuild the app\ntest\t\nlint", on: "\n", descriptions: "\t")
        #expect(items.map(\.name.first) == ["build", "test", "lint"])
        #expect(items.map(\.description) == ["Build the app", nil, nil])
    }
}

@Suite struct TemplateFilterTests {
    @Test func extensions() {
        let f = TemplateFilter(extensions: ["js", "tar.gz"])
        #expect(f.accepts("app.js", isDirectory: false))
        #expect(f.accepts("a.tar.gz", isDirectory: false))
        #expect(!f.accepts("app.ts", isDirectory: false))
        #expect(f.accepts("src/", isDirectory: true))
    }

    @Test func equalsAndRegex() {
        let f = TemplateFilter(equals: ["Makefile"], matches: #"^Dockerfile"#)
        #expect(f.accepts("Makefile", isDirectory: false))
        #expect(f.accepts("Dockerfile.dev", isDirectory: false))
        #expect(!f.accepts("README", isDirectory: false))
    }

    @Test func filterFolders() {
        var f = TemplateFilter(extensions: ["js"])
        f.filterFolders = true
        #expect(!f.accepts("src/", isDirectory: true))
    }
}

@Suite struct SpecStoreTests {
    @Test func editedSpecIsReloaded() throws {
        let dir = try temporaryDirectory()
        let file = dir + "/tool.yaml"
        try write("name: tool\nsubcommands: [{name: one}]\n", to: file)
        let store = specStore(dir)
        #expect(store.spec(named: "tool")?.subcommands?.map(\.name.first) == ["one"])
        try write("name: tool\nsubcommands: [{name: two}]\n", to: file, modified: 60)
        #expect(store.spec(named: "tool")?.subcommands?.map(\.name.first) == ["two"])
    }

    @Test func newSpecAppearsInCommands() throws {
        let dir = try temporaryDirectory()
        let store = specStore(dir)
        #expect(store.commands().isEmpty)
        try write("name: added\ndescription: New\n", to: dir + "/added.yaml")
        try touch(dir, modified: 60)
        #expect(store.commands()["added"]?.description == "New")
    }

    @Test func brokenSpecReportsError() throws {
        let dir = try temporaryDirectory()
        try write("name: bad\noptions: oops\n", to: dir + "/bad.yaml")
        let store = specStore(dir)
        #expect(store.spec(named: "bad") == nil)
        #expect(store.loadError(for: "bad") != nil)
    }

    @Test func linterFindsTypos() {
        let issues = SpecLinter.lint(yaml: "name: x\ndescripton: typo\n")
        #expect(issues.count == 1)
        #expect(issues.first?.contains("did you mean `description`") == true)
    }
}
