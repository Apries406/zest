import Foundation
@testable import ZestCore

struct FakeFileSystem: FileSystem {
    var tree: [String: [FileEntry]]
    var homeDirectory = "/Users/me"

    func list(_ path: String) -> [FileEntry] {
        var key = path
        while key.count > 1 && key.hasSuffix("/") { key.removeLast() }
        return tree[key] ?? []
    }
}

struct FakeShell: ShellRunner {
    var outputs: [String: String]

    func run(_ script: Script, cwd: String, timeout: TimeInterval) -> ShellResult {
        let key: String
        switch script {
        case .shell(let s): key = s
        case .argv(let a): key = a.joined(separator: " ")
        }
        return ShellResult(stdout: outputs[key] ?? "")
    }
}

enum Fixtures {
    static var specs: URL {
        Bundle.module.resourceURL!.appendingPathComponent("Fixtures/specs")
    }

    static let fileSystem = FakeFileSystem(tree: [
        "/work": [
            FileEntry(name: "Desktop", isDirectory: true),
            FileEntry(name: "Documents", isDirectory: true),
            FileEntry(name: "My Doc.txt", isDirectory: false),
            FileEntry(name: ".hidden", isDirectory: false),
            FileEntry(name: "notes.md", isDirectory: false),
        ],
        "/work/Desktop": [
            FileEntry(name: "graphio", isDirectory: true),
            FileEntry(name: "client", isDirectory: true),
            FileEntry(name: "todo.txt", isDirectory: false),
        ],
        "/Users/me": [FileEntry(name: "Projects", isDirectory: true)],
    ])

    static func engine(
        shell: [String: String] = ["git branch": "main\nfeature/x\n", "list-items": "a,b", "other-items": "x,y"],
        usage: UsageStore? = nil
    ) -> Engine {
        let runner = GeneratorRunner(shell: FakeShell(outputs: shell))
        runner.synchronous = true
        var settings = EngineSettings()
        settings.pathCommands = false
        return Engine(
            store: SpecStore(directories: [specs]), generators: runner,
            fileSystem: fileSystem, settings: settings, usage: usage)
    }
}

extension Engine {
    func names(_ buffer: String, aliases: [String: String] = [:], history: [String] = []) -> [String] {
        complete(CompletionRequest(buffer: buffer, cwd: "/work", aliases: aliases, history: history)).items.map(\.name)
    }

    func first(_ buffer: String) -> Completion? {
        complete(CompletionRequest(buffer: buffer, cwd: "/work")).items.first
    }
}
