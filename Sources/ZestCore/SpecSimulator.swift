import Foundation

/// Types typical command lines for a spec and checks what the engine suggests.
///
/// Catches problems a schema check cannot: a `loadSpec` pointing nowhere, JavaScript that
/// fails to load, empty or broken suggestions, subcommands that suggest nothing, slow specs.
/// Generator scripts are not run (the shell is replaced by one that prints nothing), so the
/// check is safe and fast. Used by `zest validate --deep` and CI.
public struct SpecSimulator {
    public struct Problem: Equatable, Sendable, CustomStringConvertible {
        public var spec: String
        public var line: String
        public var message: String

        public var description: String {
            line.isEmpty ? "\(spec): \(message)" : "\(spec): `\(line)` \(message)"
        }
    }

    struct SilentShell: ShellRunner {
        func run(_ script: Script, cwd: String, timeout: TimeInterval) -> ShellResult {
            ShellResult(stdout: "")
        }
    }

    public let engine: Engine
    let store: SpecStore
    /// A completion slower than this (without running scripts) is reported.
    public var slowLimit: TimeInterval = 0.75
    /// How many subcommands get their own lines checked, per level.
    public var subcommandLimit = 400
    let cwd = FileManager.default.temporaryDirectory.path

    public init(directories: [URL]) {
        store = SpecStore(directories: directories)
        let runner = GeneratorRunner(shell: SilentShell())
        runner.synchronous = true
        var settings = EngineSettings()
        settings.pathCommands = false
        settings.historySuggestions = false
        engine = Engine(store: store, generators: runner, settings: settings)
    }

    public func check(_ name: String) -> [Problem] {
        var problems: [Problem] = []
        guard let spec = store.spec(named: name) else {
            return [Problem(spec: name, line: "", message: store.loadError(for: name) ?? "cannot be loaded")]
        }
        if let error = engine.generators.companionError(spec: name) {
            problems.append(Problem(spec: name, line: "", message: "JavaScript companion: \(error)"))
        }
        walk(spec, path: [name], depth: 0, spec: name, into: &problems)
        return problems
    }

    private func walk(_ node: Subcommand, path: [String], depth: Int, spec: String, into problems: inout [Problem]) {
        var node = node
        if let load = node.loadSpec {
            guard let loaded = store.spec(named: load) else {
                problems.append(Problem(spec: spec, line: path.joined(separator: " "), message: "loadSpec `\(load)` not found"))
                return
            }
            node = loaded
            if let error = engine.generators.companionError(spec: load) {
                problems.append(Problem(spec: spec, line: path.joined(separator: " "), message: "JavaScript companion of \(load): \(error)"))
            }
        }
        let prefix = path.joined(separator: " ") + " "
        // Names with spaces (a few upstream specs have them) can never be typed as one word.
        let visible = (node.subcommands ?? []).filter { $0.hidden != true && !$0.name.first.contains(" ") }
        let options = (node.options ?? []).filter { $0.hidden != true && $0.name.all.contains { $0.hasPrefix("-") } }

        let items = complete(prefix, spec: spec, into: &problems)
        if !visible.isEmpty && items.isEmpty {
            problems.append(Problem(spec: spec, line: prefix, message: "suggests nothing, but has \(visible.count) subcommands"))
        }
        if !options.isEmpty {
            let dash = complete(prefix + "-", spec: spec, into: &problems)
            if !dash.contains(where: { $0.kind == .option }) {
                problems.append(Problem(spec: spec, line: prefix + "-", message: "suggests no options, but has \(options.count)"))
            }
        }
        // Values of the first few options that take one.
        for option in options.filter({ !$0.argList.isEmpty }).prefix(3) {
            let name = option.name.first
            if let sep = option.separator {
                _ = complete(prefix + name + sep, spec: spec, into: &problems)
            } else {
                _ = complete(prefix + name + " ", spec: spec, into: &problems)
            }
        }
        // Inserting the first suggestion must give a line the engine can continue from.
        if let first = items.first {
            let line = prefix
            let applied = Engine.apply(first, buffer: line, cursor: line.unicodeScalars.count)
            if !applied.buffer.hasPrefix(prefix) {
                problems.append(Problem(spec: spec, line: line, message: "inserting `\(first.name)` changes the text before it"))
            }
            _ = complete(applied.buffer, cursor: applied.cursor, spec: spec, into: &problems)
        }

        guard depth < 2 else { return }
        let limit = depth == 0 ? subcommandLimit : 5
        for sub in visible.prefix(limit) {
            walk(sub, path: path + [sub.name.first], depth: depth + 1, spec: spec, into: &problems)
        }
    }

    private func complete(_ line: String, cursor: Int? = nil, spec: String, into problems: inout [Problem]) -> [Completion] {
        // The first call loads the spec and its JavaScript once; time the call you'd feel while typing.
        let request = CompletionRequest(buffer: line, cursor: cursor, cwd: cwd)
        _ = engine.complete(request)
        let start = Date()
        let result = engine.complete(request)
        let elapsed = Date().timeIntervalSince(start)
        if elapsed > slowLimit {
            problems.append(Problem(spec: spec, line: line, message: String(format: "took %.2f s", elapsed)))
        }
        var seen = Set<String>()
        for item in result.items {
            if item.name.trimmingCharacters(in: .whitespaces).isEmpty {
                problems.append(Problem(spec: spec, line: line, message: "has a suggestion with an empty name"))
            }
            if item.insertText.contains(where: { $0.isNewline || ($0.asciiValue.map { $0 < 32 } ?? false) }) {
                problems.append(Problem(spec: spec, line: line, message: "`\(item.name)` inserts a newline or control character"))
            }
            if item.replaceStart > line.unicodeScalars.count || item.replaceEnd < item.replaceStart {
                problems.append(Problem(spec: spec, line: line, message: "`\(item.name)` has a bad replacement range"))
            }
            if !seen.insert("\(item.kind)|\(item.name)").inserted {
                problems.append(Problem(spec: spec, line: line, message: "suggests `\(item.name)` twice"))
            }
        }
        return result.items
    }
}
